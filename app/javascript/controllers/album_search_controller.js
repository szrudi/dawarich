// Searchable photo-album picker used on trips/new and trips/edit.
// Fetches the user's albums from all configured photo integrations once,
// filters them client-side, and also accepts a pasted album URL or raw id.

import BaseController from "./base_controller"

const UUID_PATTERN =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

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
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener("click", this.boundCloseOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnOutsideClick)
  }

  async open() {
    await this.loadAlbums()
    this.renderList(this.inputTarget.value.trim())
  }

  async filter() {
    const query = this.inputTarget.value.trim()

    if (this.matchPastedAlbum(query)) return

    // Typing invalidates a previous selection until a new one is made
    if (this.nameTarget.value && query !== this.nameTarget.value) {
      this.setAlbum(null)
    }

    await this.loadAlbums()
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

  async loadAlbums() {
    if (this.albums !== null) return

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
        },
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.albums = await response.json()
    } catch (error) {
      console.error("Failed to fetch photo albums:", error)
      this.albums = []
    }
  }

  // Recognizes a pasted album URL (matched against the configured integration
  // base URLs) or a bare album id, and selects the album directly.
  matchPastedAlbum(text) {
    if (!text || text.length < 8 || text.includes(" ")) return false

    const fromUrl = this.albumFromUrl(text)
    if (fromUrl) {
      this.applyPastedAlbum(fromUrl.source, fromUrl.id)
      return true
    }

    const listed = (this.albums || []).find((album) => album.id === text)
    if (listed) {
      this.applyPastedAlbum(listed.source, listed.id)
      return true
    }

    if (UUID_PATTERN.test(text) && text.match(UUID_PATTERN)[0] === text) {
      // A bare UUID is an Immich album id
      this.applyPastedAlbum("immich", text)
      return true
    }

    return false
  }

  albumFromUrl(text) {
    if (!text.startsWith("http")) return null

    if (this.immichUrlValue && text.startsWith(this.immichUrlValue)) {
      const match = text.match(/\/albums\/([0-9a-f-]{36})/i)
      if (match) return { source: "immich", id: match[1] }
    }

    if (this.photoprismUrlValue && text.startsWith(this.photoprismUrlValue)) {
      const match = text.match(/\/albums\/([0-9a-z]+)/i)
      if (match) return { source: "photoprism", id: match[1] }
    }

    return null
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
      const empty = document.createElement("li")
      const label = document.createElement("span")
      label.className = "px-4 py-2 text-sm opacity-60"
      label.textContent =
        this.albums && this.albums.length === 0
          ? "No albums found"
          : "No albums match your search"
      empty.appendChild(label)
      this.listTarget.appendChild(empty)
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
    if (!this.element.contains(event.target)) this.closeList()
  }
}
