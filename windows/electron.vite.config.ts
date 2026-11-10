// electron-vite 설정: main(Node) · preload · renderer(React) 세 묶음을 각각 빌드한다
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  main: {},
  preload: {},
  renderer: { plugins: [react()] },
})
