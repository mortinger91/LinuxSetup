// Scales opencode's wheel scrolling while keeping scroll_acceleration.
//
// Why: opencode ignores scroll_speed when scroll_acceleration is on, and on this
// machine KDE's per-device ScrollFactor (G502 0.5, touchpad 0.1) means the
// terminal only sends one wheel event per 2 flicks. Multiplying the accelerated
// step by MULTIPLIER restores ~1 line per flick on average, with acceleration.
//
// Also clears the fractional remainder when the scroll direction reverses
// (opentui fixed this upstream in #1761; opencode 1.19.5 still ships the old
// ScrollBox), so the first notch the other way is not swallowed.
//
// Every scroll box is a renderable with a writable `scrollAcceleration`; the
// tree is rescanned periodically because session views create new boxes.

const MULTIPLIER = 2
const RESCAN_MS = 500
const PATCHED = Symbol("scrollBoost")

function patch(node) {
  if (node[PATCHED] || !("scrollAcceleration" in node)) return
  const inner = node.scrollAcceleration
  if (!inner || typeof inner.tick !== "function") return
  node[PATCHED] = true

  node.scrollAcceleration = {
    tick: (now) => inner.tick(now) * MULTIPLIER,
    reset: () => inner.reset(),
  }

  const onMouseEvent = node.onMouseEvent
  if (typeof onMouseEvent !== "function") return
  let last
  node.onMouseEvent = function (event) {
    if (event?.type === "scroll") {
      const dir = event.scroll?.direction
      if (last && dir && dir !== last) {
        this.scrollAccumulatorX = 0
        this.scrollAccumulatorY = 0
        inner.reset()
      }
      last = dir
    }
    return onMouseEvent.call(this, event)
  }
}

function walk(node, seen = new Set()) {
  if (!node || seen.has(node)) return
  seen.add(node)
  patch(node)
  let children = []
  try {
    children = typeof node.getChildren === "function" ? node.getChildren() : []
  } catch {}
  for (const child of children) walk(child, seen)
}

const tui = async (api) => {
  const renderer = api.renderer
  if (!renderer) return
  const scan = () => {
    try {
      walk(renderer.root)
    } catch {}
  }
  scan()
  const timer = setInterval(scan, RESCAN_MS)
  timer.unref?.()
}

export default { id: "scroll-boost", tui }
