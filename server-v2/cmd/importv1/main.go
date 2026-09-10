// Command importv1 copies a live v1 Salio database into the v2 schema.
//
// Read-only on the source, so the v1 server keeps serving shops throughout. Run
// against a *snapshot* of production rather than production itself wherever
// possible: the import takes its own consistent view of each business, but a shop
// recording a debt halfway through will have that debt on one side only.
//
//	# what would be copied, changing nothing
//	go run ./cmd/importv1 -source "$V1_DSN" -dry-run
//
//	# the import, then the check that decides whether to cut over
//	go run ./cmd/importv1 -source "$V1_DSN"
//
//	# re-check an import that has already run
//	go run ./cmd/importv1 -source "$V1_DSN" -verify-only
//
// The target is whatever the .env / config points at, exactly as the API server
// and the migrate command read it — so there is one definition of "the v2
// database" and no second DSN to get wrong.
package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/codetheuri/tusk/v2/config"
	tuskdb "github.com/codetheuri/tusk/v2/database"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/database"
	"salio/server-v2/internal/dataimport"
	"salio/server-v2/internal/rbac"
)

func main() {
	sourceDSN := flag.String("source", "", "connection string for the v1 database (read-only)")
	dryRun := flag.Bool("dry-run", false, "report what would be copied, and write nothing")
	verifyOnly := flag.Bool("verify-only", false, "skip the import and only compare the two databases")
	force := flag.Bool("force", false, "import even though the target already holds businesses")
	flag.Parse()

	if *sourceDSN == "" {
		fmt.Fprintln(os.Stderr, "usage: importv1 -source <v1 dsn> [-dry-run] [-verify-only] [-force]")
		os.Exit(1)
	}

	ctx := context.Background()

	sourceDB, err := sql.Open("pgx", *sourceDSN)
	if err != nil {
		log.Fatalf("opening the v1 database: %v", err)
	}
	defer sourceDB.Close()
	if err := sourceDB.PingContext(ctx); err != nil {
		log.Fatalf("the v1 database is unreachable: %v", err)
	}
	src := dataimport.NewSource(sourceDB)

	counts, err := src.Counts(ctx)
	if err != nil {
		log.Fatalf("reading the v1 database: %v", err)
	}
	fmt.Printf("v1 holds %d businesses, %d users, %d customers, %d transactions, %d super admins\n",
		counts.Businesses, counts.Users, counts.Customers, counts.Transactions, counts.SuperAdmins)

	if *dryRun {
		seq, err := src.HighestChangeSeq(ctx)
		if err != nil {
			log.Fatalf("reading the v1 sync sequence: %v", err)
		}
		fmt.Println("dry run: nothing was written")
		fmt.Printf("v1's sync sequence has reached %d; the cutover horizon would be set above it "+
			"so every device resyncs once\n", seq)
		return
	}

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("loading the v2 configuration: %v", err)
	}
	target, err := tuskdb.Connect(cfg, logger.NewTextLogger("error"))
	if err != nil {
		log.Fatalf("connecting to the v2 database: %v", err)
	}

	// Says out loud whether row-level security binds this role. The import
	// declares a tenant per business either way, so it is correct on both — but
	// an operator running a cutover should know which protections are live.
	if err := tenant.VerifyEnforcement(target); err != nil {
		fmt.Printf("note: row-level security is not enforced for this role — %v\n", err)
	}

	if !*verifyOnly {
		sqlDB, err := target.DB()
		if err != nil {
			log.Fatalf("getting the underlying sql.DB: %v", err)
		}
		// The schema, then the permission rows the import's AssignRole calls
		// depend on. Running both here means the target can be an empty database
		// and the cutover is one command.
		if err := database.Migrator().Up(sqlDB); err != nil {
			log.Fatalf("migrating the v2 schema: %v", err)
		}
		if err := rbac.Seed(ctx, target); err != nil {
			log.Fatalf("seeding permissions: %v", err)
		}

		report, err := dataimport.NewImporter(target).Run(ctx, src, dataimport.Options{Force: *force})
		if err != nil {
			log.Fatalf("import failed: %v", err)
		}
		fmt.Printf("imported %d businesses, %d users, %d live invites, %d customers, %d transactions, %d super admins\n",
			report.Businesses, report.Users, report.Invites, report.Customers,
			report.Transactions, report.SuperAdmins)
		fmt.Printf("cutover horizon set to %d — every device's existing cursor is below it, "+
			"so each resyncs once on its first pull\n", report.Sealed)
	}

	discrepancies, err := dataimport.Verify(ctx, src, target)
	if err != nil {
		log.Fatalf("verification could not complete: %v", err)
	}

	if len(discrepancies) == 0 {
		fmt.Println("verified: row counts match and every customer balance is identical in both databases")
		return
	}

	// A non-zero exit, so a cutover script cannot proceed past a failed check by
	// accident. Balances differing is not a warning.
	fmt.Fprintf(os.Stderr, "\n%d discrepancies — DO NOT CUT OVER:\n", len(discrepancies))
	for i, d := range discrepancies {
		if i == 50 {
			fmt.Fprintf(os.Stderr, "  … and %d more\n", len(discrepancies)-50)
			break
		}
		fmt.Fprintf(os.Stderr, "  %s\n", d)
	}
	os.Exit(1)
}
