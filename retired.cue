// The corpus's RETIREMENT list — repos the corpus must never publish from again, whatever stale
// pin still names them. Validated against plugin-marketplace's `#Retired`; a retired ref declared
// by this repo's own refs list is an authoring contradiction and fails the generation.
//
// A retired repo is retired, not deleted: its tags stay cloneable, which is exactly why the list
// exists (opencharly/plugin-marketplace#63).
retired: [
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
