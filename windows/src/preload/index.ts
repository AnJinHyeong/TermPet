// preload: renderer(React)에 열어 줄 API만 골라서 window.termpet 으로 노출 (Node 전체를 열지 않음)
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron'
import type { TermPetBridge } from '../shared/ipc'

/** 구독 함수 만들기: 반환값은 useEffect cleanup 용 구독 해제 함수 */
function listen<T>(channel: string) {
  return (cb: (v: T) => void) => {
    const handler = (_e: IpcRendererEvent, v: T) => cb(v)
    ipcRenderer.on(channel, handler)
    return () => {
      ipcRenderer.removeListener(channel, handler)
    }
  }
}

const view = (new URLSearchParams(location.search).get('view') ?? 'pet') as TermPetBridge['view']

const bridge: TermPetBridge = {
  view,
  onPetState: listen('pet:state'),
  petPointer: (type) => ipcRenderer.send('pet:pointer', type),
  onBubbleState: listen('bubble:state'),
  onChime: listen('bubble:chime'),
  bubbleSize: (w, h) => ipcRenderer.send('bubble:size', w, h),
  bubbleClick: (target) => ipcRenderer.send('bubble:click', target),
  onPanelState: listen('panel:state'),
  panelAction: (a) => ipcRenderer.send('panel:action', a),
  panelSize: (h) => ipcRenderer.send('panel:size', h),
}
contextBridge.exposeInMainWorld('termpet', bridge)
