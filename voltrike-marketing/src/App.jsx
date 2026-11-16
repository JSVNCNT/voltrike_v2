import React, { useEffect, useRef, useState } from 'react';

const APK = 'https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike.apk';
const RELEASES = 'https://github.com/JSVNCNT/voltrike_v2/releases';

function Icon({ name, size = 24, className = '' }) {
  const paths = {
    arrow: <><path d="M4 12h16M14 6l6 6-6 6" /></>,
    download: <><path d="M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5" /></>,
    play: <path d="m9 5 11 7-11 7Z" />,
    pin: <><path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" /></>,
    leaf: <><path d="M20 3c1 12-4 17-11 15-7-3-4-10 2-11 3-1 6-2 9-4ZM4 22 15 11" /></>,
    shield: <><path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6Z" /><path d="m8 12 3 3 5-6" /></>,
    route: <><circle cx="6" cy="5" r="2" /><circle cx="18" cy="19" r="2" /><path d="M8 5h8a4 4 0 0 1 0 8H8a3 3 0 0 0 0 6h8" /></>,
    chat: <><path d="M20 15a3 3 0 0 1-3 3H8l-5 4V6a3 3 0 0 1 3-3h11a3 3 0 0 1 3 3Z" /><path d="M7 8h9M7 12h6" /></>,
    receipt: <><path d="m5 3 3 2 4-2 4 2 3-2v19l-3-2-4 2-4-2-3 2Z" /><path d="M9 9h6M9 13h6M9 17h3" /></>,
    check: <path d="m5 12 4 4L19 6" />,
    phone: <><rect x="6" y="2" width="12" height="20" rx="3" /><path d="M10 5h4M11 19h2" /></>,
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
    bolt: <path d="m13 2-9 12h7l-1 8 10-13h-8Z" />,
    plus: <path d="M5 12h14M12 5v14" />,
    people: <><circle cx="9" cy="7" r="3" /><path d="M2 21v-4a5 5 0 0 1 5-5h4a5 5 0 0 1 5 5v4M17 4a3 3 0 0 1 0 6m2 3a5 5 0 0 1 3 5v3" /></>,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden="true">{paths[name] || paths.arrow}</svg>;
}

function Brand({ light = false }) {
  return <a className={`brand ${light ? 'brand-light' : ''}`} href="/" aria-label="VolTrike home">
    <img src={`/images/logo-${light ? 'light' : 'dark'}.webp`} alt="" width="51" height="44" />
    <span>VolTrike<span className="brand-dot">.</span></span>
  </a>;
}

function RouteArt({ className = '' }) {
  return <svg className={`route-art ${className}`} viewBox="0 0 720 640" fill="none" aria-hidden="true">
    <path d="M-100 570C60 560 75 475 242 465s190-135 330-140 230-90 210-225" stroke="currentColor" strokeWidth="85" opacity=".06" />
    <path d="M-100 570C60 560 75 475 242 465s190-135 330-140 230-90 210-225" stroke="currentColor" strokeWidth="2" strokeDasharray="10 14" opacity=".4" />
    <path d="M52 128C48 65 110 43 167 29c-3 71-52 123-115 99Zm0 0 71-61M565 521c-5-59 51-81 108-96 0 71-47 118-108 96Zm0 0 65-61" stroke="currentColor" strokeWidth="1.5" opacity=".32" />
    <circle cx="244" cy="465" r="9" fill="currentColor" opacity=".5" /><circle cx="571" cy="325" r="9" fill="currentColor" opacity=".5" />
  </svg>;
}

function Header({ legal = false }) {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const close = (event) => { if (event.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, []);
  const prefix = legal ? '/' : '';
  return <header className="site-header">
    <div className="container nav-wrap">
      <Brand light />
      <button className="menu-toggle" type="button" aria-label={open ? 'Close navigation' : 'Open navigation'} aria-expanded={open} aria-controls="primary-nav" onClick={() => setOpen(!open)}><Icon name={open ? 'close' : 'menu'} /></button>
      <nav id="primary-nav" className={`primary-nav ${open ? 'is-open' : ''}`} aria-label="Main navigation">
        {[['The experience', 'experience'], ['How it works', 'how-it-works'], ['Our purpose', 'purpose'], ['Watch demo', 'demo']].map(([label, id]) => <a key={id} href={`${prefix}#${id}`} onClick={() => setOpen(false)}>{label}</a>)}
        <a className="btn btn-mint nav-download" href={`${prefix}#download`} onClick={() => setOpen(false)}>Get the app <Icon name="arrow" size={18} /></a>
      </nav>
    </div>
  </header>;
}

function PhoneFrame({ src, alt, className = '', priority = false }) {
  return <div className={`phone-frame ${className}`}><img src={src} alt={alt} width="512" height="1109" loading={priority ? 'eager' : 'lazy'} fetchpriority={priority ? 'high' : 'auto'} /></div>;
}

function VideoPlayer({ src, poster, title, duration, silent = false, wide = false }) {
  const [started, setStarted] = useState(false);
  const [failed, setFailed] = useState(false);
  const player = useRef(null);
  useEffect(() => {
    if (started) {
      player.current?.focus({ preventScroll: true });
      player.current?.play().catch(() => { /* Native controls remain available. */ });
    }
  }, [started]);
  return <div className={`video-player ${wide ? 'video-wide' : ''}`}>
    {started ? <video ref={player} controls playsInline tabIndex={0} preload="metadata" poster={poster} aria-label={title} muted={silent} onError={() => setFailed(true)}>
      <source src={src} type="video/mp4" />Your browser does not support video playback. <a href={src}>Open the video</a>.
    </video> : <button type="button" className="video-cover" onClick={() => setStarted(true)} aria-label={`Play ${title}`}>
      <img src={poster} alt="" loading="lazy" width="1280" height="720" />
      <span className="video-shade" /><span className="play-button"><Icon name="play" size={28} /></span>
      <span className="video-cover-caption"><span>{title}</span><span>{duration}{silent ? ' · Silent demo' : ''}</span></span>
    </button>}
    {failed && <p className="video-error" role="alert">The video could not load. <a href={src}>Open the MP4 directly</a> or try again.</p>}
  </div>;
}

const roles = [
  { name: 'Passengers', eyebrow: 'YOUR EVERYDAY RIDE', title: 'Less guesswork. More going.', text: 'See your fare before you book, follow your driver on the map, and keep your trip details in one place.',
    items: ['Fare breakdown before booking', 'Live driver and trip tracking', 'One or two drop-offs, with cash payment'], screens: ['fare-review', 'trip-progress'], labels: ['Review the fare', 'Follow your trip'], icon: 'pin' },
  { name: 'Drivers', eyebrow: 'A CLEARER WAY TO WORK', title: 'From the next request to the last drop-off.', text: 'Receive ride offers, see the pickup and destination, and move through each stage of the trip in the app.',
    items: ['Go online after TODA application approval', 'Accept offers and follow trip directions', 'Confirm cash received and review trip fares'], screens: ['driver-offer', 'driver-cash'], labels: ['Review a ride offer', 'Confirm cash received'], icon: 'route' },
  { name: 'TODA & Admin', eyebrow: 'CONNECTED LOCAL OPERATIONS', title: 'A shared view of community rides.', text: 'A dedicated web portal helps TODA and System Administrators manage their permitted drivers, rides, and reports.',
    items: ['Review driver and vehicle applications', 'See online drivers and ride activity', 'Manage reports within assigned permissions'], screens: ['admin-toda'], labels: ['TODA live-driver view'], icon: 'people' },
];

function Experience() {
  const [active, setActive] = useState(0);
  const role = roles[active];
  return <section id="experience" className="section-pad experience-section">
    <div className="container">
      <div className="section-heading"><p className="eyebrow">ONE COMMUNITY. CONNECTED.</p><h2>A little closer to<br />where you need to be.</h2><p>For the people taking the ride, driving it, and keeping it moving.</p></div>
      <div className="role-switch" role="group" aria-label="Explore VolTrike by role">{roles.map((r, i) => <button type="button" key={r.name} aria-pressed={active === i} aria-controls="role-content" className={active === i ? 'active' : ''} onClick={() => setActive(i)}><Icon name={r.icon} size={19} />{r.name}</button>)}</div>
      <div className="experience-panel row g-0 align-items-center" id="role-content" aria-label={`${role.name} features`}>
        <div className="col-lg-5"><div className="experience-copy" key={`copy-${active}`}><p className="eyebrow">{role.eyebrow}</p><h3>{role.title}</h3><p>{role.text}</p><ul className="check-list">{role.items.map(item => <li key={item}><Icon name="check" size={19} />{item}</li>)}</ul><a className="text-link" href="#demo">See it in action <Icon name="arrow" size={19} /></a></div></div>
        <div className="col-lg-7"><div className={`experience-screens ${active === 2 ? 'admin-screen' : ''}`} key={`screens-${active}`}>
          <RouteArt />
          {role.screens.map((screen, i) => <figure key={screen}>{active === 2 ? <div className="browser-frame"><div className="browser-bar"><i /><i /><i /><span>VolTrike Admin</span></div><img src={`/screens/${screen}.webp`} alt="VolTrike TODA portal showing the online-driver map and a test driver" width="1068" height="1087" loading="lazy" /></div> : <PhoneFrame src={`/screens/${screen}.webp`} alt={`VolTrike ${role.name.toLowerCase()} screen: ${role.labels[i]}`} />}<figcaption>{role.labels[i]}</figcaption></figure>)}
        </div></div>
      </div>
      <p className="screen-note">Actual application screens shown with demonstration data.</p>
    </div>
  </section>;
}

const faqs = [
  ['How do I install VolTrike?', 'Use the Download for Android button, open the downloaded APK, and confirm installation. Android may ask you to allow installation from your browser. Only use the download linked here, from the official project GitHub repository.'],
  ['What phone do I need?', 'The current test app is for Android 7.0 or later. An internet connection and the permissions required by the app are needed for booking, maps, location, and communication.'],
  ['Where are rides available?', 'VolTrike is a Bacolod-focused capstone project. Booking depends on configured service areas, allowed routes, and approved drivers being online. The website does not guarantee an available ride.'],
  ['How do I pay for a ride?', 'Payment is in cash. Review the fare in the app before booking. After the trip, the driver confirms the cash received and a receipt is available in the app.'],
  ['Can I register as a driver?', 'Yes. Driver applicants submit identity, licence, vehicle, and TODA details in the app. The responsible TODA reviews the application before a driver can receive ride offers.'],
  ['Is this the final public release?', 'This download is a capstone/test version distributed as an APK, outside Google Play. Updates are manual: use the same download link to get the latest APK. It is not an iOS release.'],
];

function Footer() {
  return <footer className="site-footer"><div className="container">
    <div className="footer-top"><div><Brand light /><p>Clean Community Mobility.</p></div><div className="footer-project"><span>A CAPSTONE BY TEAM TRACELOGY</span><p>Jose Vincent III Bayoguing  · Denro S. Maban<br />University of Negros Occidental – Recoletos</p></div></div>
    <div className="footer-bottom"><span>© {new Date().getFullYear()} VolTrike</span><div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href={RELEASES} target="_blank" rel="noreferrer">Release notes <span className="visually-hidden">(opens in a new tab)</span><Icon name="arrow" size={14} /></a></div><a className="back-top" href="#top">Back to top ↑</a></div>
  </div></footer>;
}

function Home() {
  return <>
    <Header />
    <main id="main-content">
      <section className="hero" aria-labelledby="hero-title">
        <div className="container"><div className="row align-items-center hero-row">
          <div className="col-lg-6 hero-copy"><p className="eyebrow hero-eyebrow"><span className="small-dot" />ELECTRIC RIDES. LOCAL CONNECTIONS.</p><h1 id="hero-title">A better way<br />to <span>go local.</span></h1><p className="hero-description">Meet VolTrike. Book an electric community ride, see your fare, and follow your trip—all in one app.</p><div className="hero-actions"><a href="#download" className="btn btn-mint">Try VolTrike for Android <Icon name="arrow" size={20} /></a><a href="#our-film" className="hero-film-link"><span><Icon name="play" size={17} /></span>Watch our story</a></div><div className="hero-location"><Icon name="pin" size={18} /><span>Made for community travel in Bacolod.</span></div></div>
          <div className="col-lg-6"><div className="hero-visual"><RouteArt /><div className="hero-orbit" /><span className="visual-coordinate">10.67° N / 122.95° E</span><PhoneFrame className="hero-phone" src="/screens/fare-review.webp" alt="VolTrike passenger app showing a fare breakdown before booking" priority /><div className="ride-tag"><span className="icon-square"><Icon name="bolt" size={24} /></span><span>Small rides.<strong>Everyday connections.</strong></span></div><div className="hero-vehicle"><img src="/images/etrike.webp" alt="Black electric tricycle illustration" width="1200" height="800" fetchpriority="high" /><span>ELECTRIC, WITH COMMUNITY IN MIND.</span></div></div></div>
        </div></div>
        <div className="hero-bottom"><div className="container"><span><Icon name="leaf" size={19} />Choose electric</span><span><Icon name="receipt" size={19} />See your fare</span><span><Icon name="route" size={19} />Follow your trip</span><span className="hero-bottom-wordmark">GO LOCAL. GO VOLTRIKE.</span></div></div>
      </section>

      <section className="film-section section-pad" id="our-film"><div className="container"><div className="row align-items-center g-5"><div className="col-lg-4"><p className="eyebrow">MEET VOLTRIKE</p><h2>Local rides.<br />A fresh direction.</h2><p>Getting around starts with a connection. See the idea behind VolTrike and the electric rides at the heart of it.</p><span className="film-duration"><Icon name="play" size={18} />The VolTrike film · 1 min 29 sec</span></div><div className="col-lg-8"><VideoPlayer src="/videos/voltrike-ad.mp4" poster="/images/ad-poster.jpg" title="The VolTrike story" duration="1:29" /></div></div></div></section>

      <section className="how-section section-pad" id="how-it-works"><div className="container"><div className="row align-items-end mb-5"><div className="col-lg-7"><p className="eyebrow">FROM HERE TO THERE</p><h2>Your next ride,<br />a few taps away.</h2></div><div className="col-lg-4 offset-lg-1"><p className="section-aside">A familiar journey, with the details in front of you.</p></div></div><div className="row g-4 steps-row">
        {[['01', 'pin', 'Choose your ride', 'Set your pickup and drop-off, then select an E-Trike or E-Tuktuk.'], ['02', 'receipt', 'Know the fare', 'Review the breakdown for your trip before sending a booking request.'], ['03', 'route', 'Meet. Ride. Arrive.', 'Follow the matched driver, stay in touch, and pay cash after the ride.']].map(([n, icon, title, text]) => <div className="col-md-4" key={n}><article className="step"><div className="step-top"><span>{n}</span><Icon name={icon} size={35} /></div><h3>{title}</h3><p>{text}</p></article></div>)}
      </div></div></section>

      <Experience />

      <section className="safety-section section-pad" id="safety"><div className="container"><div className="row g-5"><div className="col-lg-5"><span className="safety-emblem"><Icon name="shield" size={46} /></span><p className="eyebrow">CARE THROUGHOUT THE TRIP</p><h2>Useful tools.<br />More peace of mind.</h2><p>Clearer information and ways to raise a concern help passengers, drivers, and their TODA stay connected.</p><a className="text-link" href="#demo">Explore the app demo <Icon name="arrow" size={19} /></a></div><div className="col-lg-6 offset-lg-1 safety-items">
        {[['shield', 'Reviewed applications', 'Driver and vehicle documents go through TODA review before approval.'], ['route', 'Route awareness', 'Configured operating areas and restricted-route checks support trip guidance.'], ['chat', 'Trip communication', 'Ride chat, calls, and configurable message filtering support communication.'], ['phone', 'Reports and SOS records', 'Concerns and SOS incidents can be recorded for authorized administrator review.']].map(([icon, title, text]) => <article className="safety-item" key={title}><Icon name={icon} size={28} /><div><h3>{title}</h3><p>{text}</p></div></article>)}
        <p className="safety-note">SOS records an incident; it does not dispatch emergency services.</p>
      </div></div></div></section>

      <section className="purpose-section" id="purpose"><div className="container"><div className="purpose-panel"><RouteArt /><div className="purpose-copy"><p className="eyebrow"><Icon name="leaf" size={18} />SMALL RIDES. SHARED PURPOSE.</p><h2>Make electric<br />part of everyday.</h2><p>VolTrike promotes electric-tricycle use by making local rides easier to find and coordinate. Our aim is to encourage more sustainable community travel, in support of <strong>SDG 13: Climate Action.</strong></p><a href="https://sdgs.un.org/goals/goal13" target="_blank" rel="noreferrer" className="text-link">Learn about SDG 13 <Icon name="arrow" size={18} /><span className="visually-hidden">(opens in a new tab)</span></a></div><div className="purpose-art"><img className="purpose-vehicle" src="/images/etuktuk.webp" alt="White electric tuktuk illustration" width="1200" height="800" loading="lazy" /><img className="sdg-logo" src="/images/sdg13.webp" alt="Sustainable Development Goal 13: Climate Action" width="160" height="160" loading="lazy" /></div></div></div></section>

      <section className="demo-section section-pad" id="demo"><div className="container"><div className="demo-heading"><div><p className="eyebrow">TAKE A CLOSER LOOK</p><h2>See the journey.<br />Then try it yourself.</h2></div><p>From a passenger booking to driver and admin operations. Follow the actual system in our short, silent walkthrough.</p></div><VideoPlayer src="/videos/voltrike-demo.mp4" poster="/images/demo-poster.jpg" title="VolTrike in action" duration="2:51" silent wide /><div className="demo-chapters"><span>01 <b>Booking & the ride</b></span><span>02 <b>App exploration</b></span><span>03 <b>System & TODA admin</b></span></div></div></section>

      <section className="download-section section-pad" id="download"><div className="container"><div className="row g-5 align-items-center"><div className="col-lg-7"><p className="eyebrow">YOUR NEXT STEP</p><h2>Go local.<br /><span>Take VolTrike with you.</span></h2><p>Explore the passenger and driver experience on your Android phone.</p><a href={APK} className="btn btn-teal download-cta"><Icon name="download" size={21} />Download for Android</a><p className="download-meta">Android 7.0+ · APK download · Capstone/test version</p><p className="download-note">Install the APK and follow the prompts on your phone. Ride availability depends on configured service areas and approved drivers.</p></div><div className="col-lg-4 offset-lg-1"><div className="qr-card"><img src="/images/app-qr.svg" width="192" height="192" alt="QR code linking to the latest VolTrike Android APK" loading="lazy" /><strong>Scan. Download. Explore.</strong><span>Open your phone’s camera to get the app.</span></div></div></div></div></section>

      <section className="faq-section section-pad" id="faq"><div className="container"><div className="row g-5"><div className="col-lg-4"><p className="eyebrow">A FEW THINGS TO KNOW</p><h2>Before<br />you get going.</h2><p>Quick answers about trying VolTrike.</p></div><div className="col-lg-7 offset-lg-1 faq-list">{faqs.map(([q, a]) => <details className="faq-item" key={q}><summary>{q}<Icon name="plus" size={21} /></summary><p>{a}</p></details>)}</div></div></div></section>
    </main>
    <Footer />
  </>;
}

function LegalPage({ type }) {
  const privacy = type === 'privacy';
  const sections = privacy ? [
    ['This website', 'This is the VolTrike capstone promotion website. It explains the system and links to the Android test app. The website has no account registration, booking form, marketing contact form, or application database connection.'],
    ['Videos, fonts, and hosting', 'The videos, screenshots, and fonts are served with this website. There are no YouTube embeds or advertising trackers in the site code. The hosting provider may process request information, such as IP addresses and browser details, to deliver and protect the website.'],
    ['Downloads and external links', 'The Android download opens GitHub Releases, which is subject to GitHub’s own privacy notice. The SDG information link opens the United Nations website. Review the relevant notice when visiting an external service.'],
    ['Using the app', 'The app has a separate privacy policy presented during registration and available in the app. It covers account details, location and trip data, communication, driver documents, safety records, permitted administrator access, and your privacy choices. Review that policy before providing information.'],
    ['Questions and updates', 'For app-related privacy requests, use the in-app support and reporting options or contact the responsible VolTrike or TODA administrator. Changes to this website notice will appear here.'],
  ] : [
    ['Project and availability', 'VolTrike is a Bacolod-focused capstone project by Team Tracelogy at the University of Negros Occidental – Recoletos. The current Android download is a capstone/test APK distributed outside Google Play. Demonstration screens and videos do not guarantee a live, citywide service.'],
    ['Trying the app', 'Bookings depend on configured coverage, approved online drivers, vehicle capacity, connectivity, and applicable transport rules. Current ride payment is cash. Review fare and trip details in the app before booking. The app’s own terms and privacy policy apply when registering and using it.'],
    ['Safety tools', 'Driver applications are reviewed by the responsible TODA. Route checks support operations and do not provide government authorization or guarantee legal compliance. The SOS feature records an incident for authorized review and does not dispatch emergency services.'],
    ['Environmental purpose', 'VolTrike aims to encourage electric-tricycle use for local travel in support of SDG 13: Climate Action. This website does not claim measured emissions savings or United Nations endorsement.'],
    ['Website content and downloads', 'App screenshots and video examples demonstrate the project. Download the APK only through the project link provided here. Availability of the website, downloads, and app may change as the capstone develops.'],
  ];
  return <><Header legal /><main id="main-content" className="legal-page container"><a href="/" className="text-link">← Back to VolTrike</a><p className="eyebrow mt-5">VOLTRIKE WEBSITE</p><h1>{privacy ? 'Privacy notice' : 'Website terms'}</h1><p className="legal-updated">Updated 16 November 2026</p>{sections.map(([title, text]) => <section key={title}><h2>{title}</h2><p>{text}</p></section>)}</main><Footer /></>;
}

export default function App({ pagePath } = {}) {
  const path = pagePath ?? (typeof window === 'undefined' ? '/' : window.location.pathname);
  const legal = path.endsWith('/privacy.html') ? 'privacy' : path.endsWith('/terms.html') ? 'terms' : null;
  return <div id="top"><a className="skip-link" href="#main-content">Skip to content</a>{legal ? <LegalPage type={legal} /> : <Home />}</div>;
}
