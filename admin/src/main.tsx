import { Sentry } from './monitoring';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
// Utilities only: importing Bootstrap's grid/components would collide with
// VolTrike's existing `.row`, button, card, typography, and color system.
import 'bootstrap/dist/css/bootstrap-utilities.min.css';
import './styles.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Sentry.ErrorBoundary fallback={<main role="alert">The admin portal encountered an unexpected error. Reload the page to continue.</main>}>
      <App />
    </Sentry.ErrorBoundary>
  </StrictMode>,
);
