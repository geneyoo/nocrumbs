import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

const features = [
  {
    title: 'Real-Time Tracking',
    description:
      'NoCrumbs captures every AI action as it happens — file writes, commands, commits — and links them back to the prompt that triggered them. No after-the-fact reconstruction.',
  },
  {
    title: 'Local-First, Always',
    description:
      'Everything stays on your machine. No cloud sync, no telemetry, no third-party servers. Just a Unix socket between the CLI and a native Mac app.',
  },
  {
    title: 'CLI + Mac App',
    description:
      'A fire-and-forget CLI hook that never blocks your workflow, paired with a native macOS app for browsing your prompt-to-commit timeline.',
  },
];

function HeroSection() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className="hero hero--primary">
      <div className="container" style={{ textAlign: 'center' }}>
        <div className="hero__logo">
          <img src="/img/hero-logo.svg" alt="NoCrumbs" className="hero__logo-img" />
          <svg className="hero__crumbs" viewBox="0 0 120 50" fill="white" xmlns="http://www.w3.org/2000/svg">
            <rect className="crumb crumb--1" x="10" y="0" width="14" height="14" />
            <rect className="crumb crumb--2" x="53" y="0" width="14" height="14" />
            <rect className="crumb crumb--3" x="32" y="28" width="14" height="14" />
          </svg>
        </div>
        <h1 className="hero__title">{siteConfig.title}</h1>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', marginTop: '2rem' }}>
          <Link className="button button--primary button--lg" to="/docs/getting-started">
            Get Started
          </Link>
          <Link
            className="button button--secondary button--lg hero__btn-locked"
            href="#"
            onClick={(e) => e.preventDefault()}
          >
            GitHub
            <span className="hero__btn-soon">Coming Soon</span>
          </Link>
        </div>
        <div className="install-hint">
          <code>brew install geneyoo/tap/nocrumbs</code>
        </div>
      </div>
    </header>
  );
}

function FeaturesSection() {
  return (
    <section className="features">
      <div className="container">
        <div className="row">
          {features.map(({ title, description }, idx) => (
            <div key={idx} className={clsx('col col--4')} style={{ marginBottom: '1.5rem' }}>
              <div className="feature-card">
                <h3>{title}</h3>
                <p>{description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      <HeroSection />
      <FeaturesSection />
    </Layout>
  );
}
