// Command syncgc collects sync tombstones that no device can still need.
//
// Run deliberately, not on a timer inside the API. It deletes ledger rows, and
// the horizon it raises forces every device older than the retention to discard
// its local copy and download the shop's book again. Both are correct and
// neither should happen because a cron entry was copied from somewhere.
//
//	go run ./cmd/syncgc -age 90d -dry-run
//	go run ./cmd/syncgc -age 90d
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"time"

	"github.com/codetheuri/tusk/v2/config"
	tuskdb "github.com/codetheuri/tusk/v2/database"
	"github.com/codetheuri/tusk/v2/pkg/logger"

	"salio/server-v2/internal/syncengine"
)

func main() {
	age := flag.Duration("age", syncengine.DefaultMaxOfflineAge,
		"how long a deleted row is kept, matching the maximum offline age devices are trusted for")
	dryRun := flag.Bool("dry-run", false, "report what would be collected without deleting anything")
	flag.Parse()

	if *age < 24*time.Hour {
		// A retention shorter than a day would invalidate the cursor of a device
		// that was merely switched off overnight.
		log.Fatalf("-age must be at least 24h; %s would force a resync on ordinary use", *age)
	}

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("failed to load configuration: %v", err)
	}

	db, err := tuskdb.Connect(cfg, logger.NewTextLogger("error"))
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}

	if *dryRun {
		log.Printf("dry run: nothing will be deleted")
		log.Printf("would collect deleted rows last touched before %s",
			time.Now().UTC().Add(-*age).Format(time.RFC3339))
		return
	}

	report, err := syncengine.NewMaintenance(db).PurgeTombstones(context.Background(), *age)
	if err != nil {
		log.Fatalf("purge failed: %v", err)
	}

	fmt.Printf("swept %d businesses: %d customers, %d transactions, %d sales, %d stock requests, "+
		"%d suppliers, %d supplier entries, %d push records collected\n",
		report.Businesses, report.Customers, report.Transactions, report.Sales, report.StockRequests,
		report.Suppliers, report.SupplierTxs, report.Operations)
	fmt.Printf("tombstone horizon is now %d — a device pulling with a cursor at or below that is told to resync\n",
		report.Horizon)
}
