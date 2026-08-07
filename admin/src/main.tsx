import { Sentry } from './monitoring';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './styles.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Sentry.ErrorBoundary fallback={<main role="alert">The admin portal encountered an unexpected error. Reload the page to continue.</main>}>
      <App />
    </Sentry.ErrorBoundary>
  </StrictMode>,
);
