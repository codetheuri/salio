// Command createadmin registers a Salio platform operator.
//
// There is deliberately no HTTP route that does this. A sign-up endpoint for an
// account that can read every business on the platform is a permanent liability
// however carefully it is guarded; creating one requires database access, which
// is a boundary that already exists.
//
//	SALIO_ADMIN_PASSWORD=... go run ./cmd/createadmin -name "Jo" -email jo@salio.co.ke
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/codetheuri/tusk/v2/config"
	tuskdb "github.com/codetheuri/tusk/v2/database"
	"github.com/codetheuri/tusk/v2/pkg/logger"

	"salio/server-v2/internal/console"
)

// minPasswordLength is a floor, not a policy. This account has more reach than
// any other in the system, and twelve characters is the least that should be
// possible to type into it.
const minPasswordLength = 12

func main() {
	name := flag.String("name", "", "the operator's name")
	email := flag.String("email", "", "the email they sign in with")
	flag.Parse()

	if strings.TrimSpace(*name) == "" || strings.TrimSpace(*email) == "" {
		fmt.Fprintln(os.Stderr, "usage: createadmin -name <name> -email <email>")
		fmt.Fprintln(os.Stderr, "the password is read from SALIO_ADMIN_PASSWORD, or from stdin")
		os.Exit(1)
	}

	password, err := readPassword()
	if err != nil {
		log.Fatalf("reading the password: %v", err)
	}
	if len(password) < minPasswordLength {
		log.Fatalf("the password must be at least %d characters", minPasswordLength)
	}

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("failed to load configuration: %v", err)
	}

	db, err := tuskdb.Connect(cfg, logger.NewTextLogger("error"))
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}

	svc := console.NewService(console.NewRepository(db))
	admin, err := svc.CreateAdmin(context.Background(),
		strings.TrimSpace(*name), strings.ToLower(strings.TrimSpace(*email)), password)
	if err != nil {
		log.Fatalf("could not create the admin: %v", err)
	}

	fmt.Printf("created super admin %s <%s> (%s)\n", admin.Name, admin.Email, admin.ID)
}

// readPassword takes the password from the environment, or from stdin.
//
// Never from a command-line flag: arguments are visible to every process on the
// machine through /proc and land verbatim in shell history, which is a poor
// place for the credential to the platform console. v1's `make create-admin
// PASSWORD=…` did exactly that.
func readPassword() (string, error) {
	if p := os.Getenv("SALIO_ADMIN_PASSWORD"); p != "" {
		return p, nil
	}

	fmt.Fprint(os.Stderr, "Password: ")
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}
