// Pure parsing for the trip-form album picker: recognizes a pasted album URL
// (matched against the user's configured integration base URLs), an album id
// that appears in the fetched albums list, or a bare Immich album UUID.
// Kept free of DOM/Stimulus so it can be unit-tested with node --test.

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function stripTrailingSlash(url) {
  return url ? url.replace(/\/+$/, "") : url
}

// Returns { source, id } when the text is an album URL, null otherwise.
// A URL under a configured base is attributed to that source directly.
// Other hosts are still recognized by path shape: Dawarich is often
// configured with an integration's internal Docker URL while the user
// browses (and copies album links from) an external URL, so the host
// can't be required to match (see upstream discussion #1782). The shape
// fallback is gated on the source being configured at all, so a paste
// can't select an album no integration can serve.
export function albumFromUrl(text, { immichUrl, photoprismUrl } = {}) {
  if (!text?.startsWith("http")) return null

  const immichBase = stripTrailingSlash(immichUrl)
  if (immichBase && text.startsWith(`${immichBase}/`)) {
    const match = text.match(/\/albums\/([0-9a-f-]{36})/i)
    if (match) return { source: "immich", id: match[1] }
  }

  const photoprismBase = stripTrailingSlash(photoprismUrl)
  if (photoprismBase && text.startsWith(`${photoprismBase}/`)) {
    const match = text.match(/\/albums\/([0-9a-z]+)/i)
    if (match) return { source: "photoprism", id: match[1] }
  }

  // Unknown host: infer the source from the path shape. Immich album ids
  // are UUIDs; PhotoPrism album uids are non-UUID alphanumerics under
  // /library/albums/.
  if (immichUrl) {
    const match = text.match(
      /\/albums\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i,
    )
    if (match) return { source: "immich", id: match[1] }
  }

  if (photoprismUrl) {
    const match = text.match(/\/library\/albums\/([0-9a-z]+)/i)
    if (match) return { source: "photoprism", id: match[1] }
  }

  return null
}

// Returns { source, id } when the text unambiguously identifies an album:
// a URL under a configured base, an id present in the albums list, or a
// bare UUID (Immich album ids are UUIDs — only when Immich is configured,
// so a PhotoPrism-only user can't save an album no integration can serve).
export function matchAlbumInput(
  text,
  { immichUrl, photoprismUrl, albums } = {},
) {
  if (!text || text.length < 8 || text.includes(" ")) return null

  const fromUrl = albumFromUrl(text, { immichUrl, photoprismUrl })
  if (fromUrl) return fromUrl

  const listed = (albums || []).find((album) => album.id === text)
  if (listed) return { source: listed.source, id: listed.id }

  if (immichUrl && UUID_PATTERN.test(text)) {
    return { source: "immich", id: text }
  }

  return null
}
