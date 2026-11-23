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
