// preload: renderer(React)에 열어 줄 API만 골라서 window.termpet 으로 노출 (Node 전체를 열지 않음)
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron'
import type { PetFrameState, TermPetBridge } from '../shared/ipc'

const bridge: TermPetBridge = {
  onState(cb) {
    const handler = (_e: IpcRendererEvent, s: PetFrameState) => cb(s)
    ipcRenderer.on('pet:state', handler)
    return () => ipcRenderer.removeListener('pet:state', handler) // useEffect cleanup용
  },
}
contextBridge.exposeInMainWorld('termpet', bridge)
