// /refreshclaude: hands the current session ID (or "new") to the zsh `opencode` wrapper and exits.
// The wrapper (in ~/.zshrc) runs claude, then relaunches opencode on that session.
import { writeFileSync } from "node:fs"

const tui = async (api) => {
  api.keymap.registerLayer({
    commands: [
      {
        name: "refreshclaude",
        title: "Refresh Claude auth and reopen this session",
        category: "Session",
        namespace: "palette",
        slashName: "refreshclaude",
        run() {
          const file = process.env.OC_RESTART_FILE
          const route = api.route.current
          if (!file) {
            api.ui.toast({ variant: "error", message: "Not launched via the zsh opencode wrapper: run `source ~/.zshrc`, then relaunch" })
            return
          }
          // Auto-approve state isn't exposed to plugins; the built-in toggle's title reflects it.
          const toggle = api.keymap
            .getCommandEntries({ namespace: "palette", visibility: "registered" })
            .find((entry) => entry.command.name === "permission.mode")
          const auto = String(toggle?.command.title ?? "").startsWith("Disable")
          // "new" tells the wrapper to relaunch plain opencode (no session to reopen).
          const id = route.name === "session" ? route.params.sessionID : "new"
          writeFileSync(file, auto ? `${id} auto` : id)
          api.keymap.dispatchCommand("app.exit")
        },
      },
    ],
  })
}

export default { id: "refreshclaude", tui }
