// the page's bridge to main.cjs: nox.call(op, args) -> Promise, nox.on(handler(name, data))
"use strict";
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("nox", {
    call: (op, args) => ipcRenderer.invoke("nox", op, args),
    on: fn => ipcRenderer.on("nox-event", (_e, name, data) => fn(name, data)),
});
