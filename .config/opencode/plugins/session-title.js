// Плагин: имя сессии = "<имя проекта> <дата> <время>"
// Имя проекта берётся из каталога САМОЙ сессии (event.properties.info.directory),
// а не из каталога запуска плагина. Дочерние (субагентные) сессии не трогаем.
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const debugFile = path.join(os.homedir(), ".config", "opencode", "session-title-debug.log")
function log(msg) {
  try { fs.appendFileSync(debugFile, `[${new Date().toISOString()}] ${msg}\n`, "utf8") } catch (e) {}
}

export default async ({ client, directory, worktree }) => {
  const pad = (n) => String(n).padStart(2, "0")
  const timestamp = () => {
    const d = new Date()
    return (
      `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
      ` ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
    )
  }
  const projectName = (dir) => {
    const base = String(dir || "").replace(/[\\/]+$/, "").split(/[\\/]/).filter(Boolean).pop()
    return base || "opencode"
  }
  const isOurFormat = (title) => /^.+? \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(String(title || ""))

  return {
    event: async ({ event }) => {
      try {
        if (!event) return
        const t = event.type
        if (t !== "session.created" && t !== "session.updated") return

        const info = (event.properties && event.properties.info) || {}
        const sid = info.id
        if (!sid) return
        if (info.parentID) return // дочерние (субагентные) сессии — не трогаем

        const dir = info.directory || directory || worktree || ""
        const title = `${projectName(dir)} ${timestamp()}`

        if (t === "session.created") {
          await client.session.update({ path: { id: sid }, body: { title } })
          log(`session.created  ${sid}  ->  ${title}`)
          return
        }

        // session.updated: переименовываем, если заголовок не в нашем формате
        // (покрывает и сессии, созданные до загрузки плагина)
        if (!isOurFormat(info.title)) {
          await client.session.update({ path: { id: sid }, body: { title } })
          log(`session.updated  ${sid}  ->  ${title}  (было: ${info.title})`)
        }
      } catch (e) {
        log(`ERROR ${e && e.message}`)
      }
    },
  }
}
