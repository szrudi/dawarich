import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// Loaded via a data: URL so node treats the extensionless-ESM .js source as a
// module regardless of node version (same technique as the other JS tests).
const source = await readFile(
  new URL("../../app/javascript/services/album_paste.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { albumFromUrl, matchAlbumInput } = await import(moduleUrl)

const config = {
  immichUrl: "https://immich.example.com",
  photoprismUrl: "https://photos.example.com/",
  albums: [
    { source: "photoprism", id: "aqnzih81icziiyae", name: "Belgium 2026" },
    {
      source: "immich",
      id: "0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c",
      name: "Walks",
    },
  ],
}

test("albumFromUrl recognizes an Immich album URL", () => {
  assert.deepEqual(
    albumFromUrl(
      "https://immich.example.com/albums/0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c",
      config,
    ),
    { source: "immich", id: "0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c" },
  )
})

test("albumFromUrl recognizes a PhotoPrism library URL despite a trailing slash in the base", () => {
  assert.deepEqual(
    albumFromUrl(
      "https://photos.example.com/library/albums/aqnzih81icziiyae/view",
      config,
    ),
    { source: "photoprism", id: "aqnzih81icziiyae" },
  )
})

test("albumFromUrl rejects URLs on unconfigured hosts", () => {
  assert.equal(
    albumFromUrl(
      "https://evil.example.org/albums/0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c",
      config,
    ),
    null,
  )
})

test("albumFromUrl rejects non-URLs and missing config", () => {
  assert.equal(albumFromUrl("not a url", config), null)
  assert.equal(albumFromUrl("https://x.example/albums/abc", {}), null)
})

test("matchAlbumInput finds a listed album by bare id", () => {
  assert.deepEqual(matchAlbumInput("aqnzih81icziiyae", config), {
    source: "photoprism",
    id: "aqnzih81icziiyae",
  })
})

test("matchAlbumInput treats a bare UUID as an Immich album when Immich is configured", () => {
  assert.deepEqual(
    matchAlbumInput("1f325dce-7b30-4a3f-b55f-0000cdfd06de", config),
    { source: "immich", id: "1f325dce-7b30-4a3f-b55f-0000cdfd06de" },
  )
})

test("matchAlbumInput refuses a bare UUID when Immich is not configured", () => {
  assert.equal(
    matchAlbumInput("1f325dce-7b30-4a3f-b55f-0000cdfd06de", {
      photoprismUrl: "https://photos.example.com",
      albums: [],
    }),
    null,
  )
})

test("matchAlbumInput ignores search-like text", () => {
  assert.equal(matchAlbumInput("belgium trip", config), null)
  assert.equal(matchAlbumInput("short", config), null)
  assert.equal(matchAlbumInput("", config), null)
  assert.equal(matchAlbumInput("unlisted-nonuuid-id", config), null)
})

test("matchAlbumInput works before the albums list has loaded (albums null)", () => {
  const noAlbums = { ...config, albums: null }
  assert.deepEqual(
    matchAlbumInput(
      "https://photos.example.com/library/albums/aqnzih81icziiyae/view",
      noAlbums,
    ),
    { source: "photoprism", id: "aqnzih81icziiyae" },
  )
})
