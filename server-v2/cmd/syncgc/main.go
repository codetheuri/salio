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
	"os"
	"os/signal"
	"syscall"
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
	every := flag.Duration("every", 0,
		"keep running and sweep at this interval (e.g. 24h) instead of once — for a container with no cron")
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

	m := syncengine.NewMaintenance(db)
	if *every == 0 {
		if err := sweep(context.Background(), m, *age); err != nil {
			log.Fatalf("purge failed: %v", err)
		}
		return
	}

	// Scheduled mode. A failed sweep is logged and retried at the next tick
	// rather than ending the process: a sweep that fails is safe (the horizon
	// is raised only by one that succeeds), and a scheduler that dies on the
	// first network blip would quietly stop collecting forever.
	if *every < time.Hour {
		log.Fatalf("-every must be at least 1h; sweeping more often only adds load")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	log.Printf("sweeping every %s", *every)
	for {
		if err := sweep(ctx, m, *age); err != nil {
			log.Printf("purge failed, will retry in %s: %v", *every, err)
		}
		select {
		case <-ctx.Done():
			log.Printf("stopping")
			return
		case <-time.After(*every):
		}
	}
}

func sweep(ctx context.Context, m *syncengine.Maintenance, age time.Duration) error {
	report, err := m.PurgeTombstones(ctx, age)
	if err != nil {
		return err
	}
	fmt.Printf("swept %d businesses: %d customers, %d transactions, %d sales, %d stock requests, "+
		"%d suppliers, %d supplier entries, %d push records collected\n",
		report.Businesses, report.Customers, report.Transactions, report.Sales, report.StockRequests,
		report.Suppliers, report.SupplierTxs, report.Operations)
	fmt.Printf("tombstone horizon is now %d — a device pulling with a cursor at or below that is told to resync\n",
		report.Horizon)
	return nil
}
