// Searchable photo-album picker used on trips/new and trips/edit.
// Fetches the user's albums from all configured photo integrations once,
// filters them client-side, and also accepts a pasted album URL or raw id
// (parsing lives in services/album_paste for unit testing).
//
// The hidden fields are the source of truth: the selection only changes on
// an explicit action (picking a suggestion, pasting an id/URL, or the clear
// button) — typing in the search box never silently drops a saved album.

import { matchAlbumInput } from "services/album_paste"
import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["input", "list", "source", "id", "name"]
  static values = {
    url: String,
    apiKey: String,
    immichUrl: String,
    photoprismUrl: String,
  }

  connect() {
    this.albums = null
    this.albumsPromise = null
    this.loadFailed = false
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener("click", this.boundCloseOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnOutsideClick)
    this.closeList()
  }

  async open() {
    await this.loadAlbums()
    this.renderList(this.inputTarget.value.trim())
  }

  async filter() {
    await this.loadAlbums()

    const query = this.inputTarget.value.trim()
    if (this.matchPastedAlbum(query)) return

    this.renderList(query)
  }

  select(event) {
    const { source, id, name } = event.currentTarget.dataset
    this.setAlbum({ source, id, name })
    this.inputTarget.value = name
    this.closeList()
  }

  clear() {
    this.setAlbum(null)
    this.inputTarget.value = ""
    this.closeList()
  }

  setAlbum(album) {
    this.sourceTarget.value = album ? album.source : ""
    this.idTarget.value = album ? album.id : ""
    this.nameTarget.value = album ? album.name : ""
  }

  loadAlbums() {
    this.albumsPromise ||= this.fetchAlbums()
    return this.albumsPromise
  }

  async fetchAlbums() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
        },
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.albums = await response.json()
      this.loadFailed = false
    } catch (error) {
      console.error("Failed to fetch photo albums:", error)
      // Leave albums unset and drop the memoized promise so the next
      // interaction retries instead of showing "No albums found" forever.
      this.albums = null
      this.loadFailed = true
      this.albumsPromise = null
    }
  }

  matchPastedAlbum(text) {
    const match = matchAlbumInput(text, {
      immichUrl: this.immichUrlValue,
      photoprismUrl: this.photoprismUrlValue,
      albums: this.albums,
    })
    if (!match) return false

    this.applyPastedAlbum(match.source, match.id)
    return true
  }

  applyPastedAlbum(source, id) {
    const listed = (this.albums || []).find(
      (album) => album.source === source && album.id === id,
    )
    const name = listed ? listed.name : id

    this.setAlbum({ source, id, name })
    this.inputTarget.value = name
    this.closeList()
  }

  renderList(query) {
    const albums = this.filteredAlbums(query)
    this.listTarget.textContent = ""

    if (albums.length === 0) {
      this.appendEmptyState()
    } else {
      const sources = [...new Set(albums.map((album) => album.source))]
      for (const source of sources) {
        if (sources.length > 1) this.appendSourceHeader(source)
        for (const album of albums.filter((a) => a.source === source)) {
          this.appendAlbumItem(album)
        }
      }
    }

    this.listTarget.classList.remove("hidden")
  }

  appendEmptyState() {
    const empty = document.createElement("li")
    const label = document.createElement("span")
    label.className = "px-4 py-2 text-sm opacity-60"
    if (this.loadFailed) {
      label.textContent =
        "Couldn't load albums — you can still paste an album URL"
    } else if (this.albums && this.albums.length === 0) {
      label.textContent = "No albums found"
    } else {
      label.textContent = "No albums match your search"
    }
    empty.appendChild(label)
    this.listTarget.appendChild(empty)
  }

  filteredAlbums(query) {
    if (!this.albums) return []
    if (!query) return this.albums

    const lowered = query.toLowerCase()
    return this.albums.filter((album) =>
      (album.name || "").toLowerCase().includes(lowered),
    )
  }

  appendSourceHeader(source) {
    const item = document.createElement("li")
    item.className = "menu-title"
    const label = document.createElement("span")
    label.textContent = source === "immich" ? "Immich" : "PhotoPrism"
    item.appendChild(label)
    this.listTarget.appendChild(item)
  }

  appendAlbumItem(album) {
    const item = document.createElement("li")
    const button = document.createElement("button")
    button.type = "button"
    button.className = "flex justify-between"
    button.dataset.source = album.source
    button.dataset.id = album.id
    button.dataset.name = album.name || album.id
    button.dataset.action = "album-search#select"

    const name = document.createElement("span")
    name.textContent = album.name || album.id
    button.appendChild(name)

    if (album.photo_count != null) {
      const count = document.createElement("span")
      count.className = "badge badge-ghost badge-sm"
      count.textContent = album.photo_count
      button.appendChild(count)
    }

    item.appendChild(button)
    this.listTarget.appendChild(item)
  }

  closeList() {
    this.listTarget.classList.add("hidden")
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return

    this.closeList()
    // Restore the canonical display: if an album is selected, the input
    // shows its name again, discarding any dangling search text.
    if (
      this.nameTarget.value &&
      this.inputTarget.value.trim() !== this.nameTarget.value
    ) {
      this.inputTarget.value = this.nameTarget.value
    }
  }
}
