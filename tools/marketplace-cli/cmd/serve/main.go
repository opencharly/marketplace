// Command serve is the OUT-OF-PROCESS entrypoint for the marketplace plugin.
//
// This module is a THIN RE-EXPORT SHIM. The generator itself lives in the external module
// github.com/opencharly/plugin-marketplace/candy/plugin-marketplace; nothing is
// reimplemented here. The shim exists so THIS repo can DECLARE the `marketplace` command
// (tools/marketplace-cli/charly.yml `plugin.providers`) and have the host build a real
// binary for it from a directory inside this repo — the plugin candy's `source:` field is
// identity metadata, not a fetch instruction, so the build resolves through this module's
// own go.mod require.
//
// Without it, `charly marketplace generate` cannot run from this repo at all: the word only
// enters the CLI grammar when charly runs inside a project whose prescan declares it, and a
// remote candy ref does NOT register a command word. CI had to `cd` into a charly checkout
// purely to borrow the grammar.
package main

import (
	marketplace "github.com/opencharly/plugin-marketplace/candy/plugin-marketplace"
	"github.com/opencharly/sdk"
)

func main() {
	sdk.Main(marketplace.NewProvider(), marketplace.NewMeta(), marketplace.CliMain)
}
