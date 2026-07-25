import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // The approved PSGC location source and shared logo live in the repository
  // assets folder. Vite publishes them without adding the nationwide data to
  // the initial JavaScript bundle.
  publicDir: '../assets',
});
