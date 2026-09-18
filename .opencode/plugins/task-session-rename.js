// task-session-rename.js — плагин OpenCode для проекта AIS.
// Назначение: при вводе команды "TASK <ключ>" в новой сессии автоматически переименовать
// текущую сессию по шаблону "<ключ> YYYY-MM-DD HH:MM" (без участия пользователя).
// Повторный "TASK <тот же ключ>" в уже переименованной сессии — игнорируется.
// Загружается автоматически из .opencode/plugins/ при старте сессии в проекте PROD.

export const TaskSessionRenamePlugin = async ({ client }) => {
  const normalizeTitle = (value) => {
    const s = value && value.title ? value.title : null
    if (s) return String(s)
    const d = value && value.data && value.data.title ? value.data.title : null
    if (d) return String(d)
    return ""
  }

  return {
    event: async ({ event }) => {
      if (!event || event.type !== "message.part.updated") return

      const part = event.properties && event.properties.part
      if (!part || part.type !== "text") return

      const sessionID = part.sessionID
      const messageID = part.messageID
      if (!sessionID || !messageID) return

      const text = (part.text || "").trim()
      const m = /^TASK\s+(SUPRT-\d+|SYBASE-\d+|BSI-\d+|[A-Z]{2,}-\d+)/i.exec(text)
      if (!m) return
      const key = m[1].toUpperCase()

      try {
        const message = await client.message.get({ sessionID, messageID })
        const role = message && message.role ? message.role : (message && message.data ? message.data.role : "")
        if (role !== "user") return

        const session = await client.session.get({ sessionID })
        const current = normalizeTitle(session)
        if (current.toUpperCase().indexOf(key) !== -1) return

        const now = new Date()
        const pad = (n) => String(n).padStart(2, "0")
        const stamp = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate()) + " " + pad(now.getHours()) + ":" + pad(now.getMinutes())

        await client.session.update({ sessionID, title: key + " " + stamp })

        if (client.app && client.app.log) {
          await client.app.log({
            body: {
              service: "task-session-rename",
              level: "info",
              message: "Session renamed: " + sessionID + " -> " + key + " " + stamp,
            },
          })
        }
      } catch (err) {
        // Тихий отказ: переименование не должно ломать обработку сообщения.
      }
    },
  }
}