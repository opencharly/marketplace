// The corpus's RETIREMENT list — repos the corpus must never publish from again, whatever stale
// pin still names them. Validated against plugin-marketplace's `#Retired`; a retired ref declared
// by this repo's own refs list is an authoring contradiction and fails the generation.
//
// A retired repo is retired, not deleted: its tags stay cloneable, which is exactly why the list
// exists (opencharly/plugin-marketplace#63).
retired: [
	// Retired by opencharly/opencharly#1292; the refs list still named them.
	"github.com/opencharly/pod-jupyter-ml",
	"github.com/opencharly/pod-unsloth-studio",
	"github.com/opencharly/pod-marimo",
	// The desktop/selkies/maps/AgentTeams closure retired by opencharly/opencharly#1293.
	// Archived/drained skill sources the closure's cards come from; a stale tag
	// must never republish their cards.
	"github.com/opencharly/layer-charly-selkies",
	"github.com/opencharly/layer-charly-filebrowser",
	"github.com/opencharly/layer-a11y-tools",
	"github.com/opencharly/layer-agentteams",
	"github.com/opencharly/layer-agentteams-cli",
	"github.com/opencharly/layer-agentteams-openclaw",
	"github.com/opencharly/layer-agentteams-snapshot",
	"github.com/opencharly/layer-android-apidemos",
	"github.com/opencharly/layer-android-sdk",
	"github.com/opencharly/layer-android-test-apps",
	"github.com/opencharly/layer-chrome-sway",
	"github.com/opencharly/layer-cstream-desktop",
	"github.com/opencharly/layer-debug-tools",
	"github.com/opencharly/layer-fastfetch",
	"github.com/opencharly/layer-gst-wayland-display",
	"github.com/opencharly/layer-heroic",
	"github.com/opencharly/layer-maplibre-versatiles-styler",
	"github.com/opencharly/layer-notebook-osm",
	"github.com/opencharly/layer-pavucontrol",
	"github.com/opencharly/layer-selkies-kde-desktop",
	"github.com/opencharly/layer-shortbread",
	"github.com/opencharly/layer-steam",
	"github.com/opencharly/layer-sway-desktop",
	"github.com/opencharly/layer-sway-desktop-vnc",
	"github.com/opencharly/layer-thunar",
	"github.com/opencharly/layer-versatiles-fonts",
	"github.com/opencharly/layer-versatiles-style",
	"github.com/opencharly/layer-wf-recorder",
	"github.com/opencharly/layer-wl-overlay",
	"github.com/opencharly/layer-wl-record-pixelflux",
	"github.com/opencharly/layer-wl-screenshot-grim",
	"github.com/opencharly/layer-wl-screenshot-pixelflux",
	"github.com/opencharly/layer-wl-tools",
	"github.com/opencharly/layer-xdg-portal",
	"github.com/opencharly/layer-xfce4-terminal",
	"github.com/opencharly/pi-asciinema",
	"github.com/opencharly/pi-fabric",
	"github.com/opencharly/pi-lsp",
	"github.com/opencharly/pi-review-action",
	"github.com/opencharly/pod-agentteams-controller",
	"github.com/opencharly/pod-agentteams-element",
	"github.com/opencharly/pod-agentteams-higress",
	"github.com/opencharly/pod-agentteams-manager",
	"github.com/opencharly/pod-agentteams-matrix",
	"github.com/opencharly/pod-agentteams-minio",
	"github.com/opencharly/pod-agentteams-worker",
	"github.com/opencharly/pod-airflow",
	"github.com/opencharly/pod-android-emulator-layer",
	"github.com/opencharly/pod-appium-server",
	"github.com/opencharly/pod-charly-versa",
	"github.com/opencharly/pod-chrome-cdp",
	"github.com/opencharly/pod-chrome-devtools-mcp",
	"github.com/opencharly/pod-chrome-headless",
	"github.com/opencharly/pod-crabbox-browser",
	"github.com/opencharly/pod-cstream",
	"github.com/opencharly/pod-filebrowser",
	"github.com/opencharly/pod-hyprland",
	"github.com/opencharly/pod-kde-nested",
	"github.com/opencharly/pod-kde-selkies",
	"github.com/opencharly/pod-kde-vnc",
	"github.com/opencharly/pod-labwc",
	"github.com/opencharly/pod-maputnik",
	"github.com/opencharly/pod-osm-tools",
	"github.com/opencharly/pod-pmtiles-viewer",
	"github.com/opencharly/pod-selkies",
	"github.com/opencharly/pod-selkies-core",
	"github.com/opencharly/pod-selkies-desktop",
	"github.com/opencharly/pod-sway",
	"github.com/opencharly/pod-swaync",
	"github.com/opencharly/pod-versatiles",
	"github.com/opencharly/pod-versatiles-frontend",
	"github.com/opencharly/pod-waybar",
	"github.com/opencharly/pod-waybar-labwc",
	"github.com/opencharly/pod-wayvnc",
	"github.com/opencharly/rpiv-todo",
	"github.com/opencharly/vm-nvidia",
	// ML folded into `immich` itself (Immich v3.4.2): the separate ML pod is archived, and old
	// distro trees still compose it from stale pins (opencharly/opencharly#1225).
	"github.com/opencharly/pod-immich-ml",
	// The drained immich concept carrier. Its current tag publishes nothing (the candy is a
	// documented no-op after the drain), but an old tag still carries `immich-ml-layer`, whose
	// body composes the retired pod above — a live skill pointing at a retired repo.
	"github.com/opencharly/layer-charly-immich",
]

// Individual CARDS whose thing was consolidated or removed while its owner repo lives on
// (opencharly/plugin-marketplace#64). Their nodes survive only in the owners' OLD tags; without
// this list a stale edge could republish them, and the docs generator would project them.
retired_skills: [
	// Cards whose owner repo survives but whose node was removed by the same retirement.
	"versa/versa",
	"selkies/selkies-kde",
	"selkies/selkies-kde-nvidia",
	"selkies/selkies-labwc",
	"selkies/selkies-labwc-nvidia",
	"selkies/sway-browser-vnc",
	// layer-openclaw publishes one `openclaw` candy/box; these four describe variants that were
	// consolidated into it.
	"openclaw/openclaw-desktop",
	"openclaw/openclaw-full",
	"openclaw/openclaw-full-layer",
	"openclaw/openclaw-full-ml-layer",
	// pod-herdr publishes the skill as `herdr-box` now.
	"automation/herdr",
	// distro-fedora's current tree carries neither.
	"coder/fedora-coder",
	"distros/fedora-test",
	// No live coder owner publishes them: distro-debian and distro-ubuntu carry neither card,
	// and the references they had in other coder skills were removed with them.
	"coder/debian-coder",
	"coder/ubuntu-coder",
]
