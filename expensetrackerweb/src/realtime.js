import { useEffect, useRef } from "react";
import { io } from "socket.io-client";
import { API_BASE, setSocketId } from "./api.js";

// One live connection to the backend (backend/services/realtime.js). A company page joins its room and hears
// { companyId, topics } after anyone else changes something there, so it reloads only the parts that changed.
let socket = null;

function getSocket() {
  if (!socket) {
    socket = io(API_BASE, { transports: ["websocket", "polling"], reconnectionDelayMax: 10000 });
    // our own writes carry this id, so the server doesn't echo them back to us
    socket.on("connect", () => setSocketId(socket.id));
    socket.on("disconnect", () => setSocketId(null));
  }
  return socket;
}

// onChange(topics): topics such as ["expenses", "balances", "ledger"]; ["*"] after a reconnect (anything may
// have changed while offline).
export function useCompanyLive(companyId, userId, onChange) {
  const handler = useRef(onChange);
  useEffect(() => {
    handler.current = onChange;
  }, [onChange]);

  useEffect(() => {
    if (!companyId || !userId) return undefined;
    const s = getSocket();
    let firstConnect = !s.connected;
    const join = () => s.emit("join", { companyId, userId });
    const onConnect = () => {
      join();
      if (!firstConnect) handler.current(["*"]);
      firstConnect = false;
    };
    const onEvent = (event) => {
      if (event && String(event.companyId) === String(companyId)) handler.current(event.topics || ["*"]);
    };
    if (s.connected) join();
    s.on("connect", onConnect);
    s.on("company:changed", onEvent);
    return () => {
      s.off("connect", onConnect);
      s.off("company:changed", onEvent);
      s.emit("leave", { companyId });
    };
  }, [companyId, userId]);
}
