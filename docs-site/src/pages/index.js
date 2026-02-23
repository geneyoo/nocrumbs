import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

const features = [
  {
    title: 'Prompt → Commit',
    description:
      'Every file write, every edit, every commit — linked back to the prompt that caused it.',
  },
  {
    title: 'Built for CLI Agents',
    description:
      'Claude Code, Codex CLI, aider — no IDE required. NoCrumbs hooks in at the terminal level and stays out of your way.',
  },
  {
    title: 'Local. Always.',
    description:
      'No cloud, no telemetry, no accounts. A Unix socket, a SQLite database, and your machine. That\'s it.',
  },
  {
    title: 'Secure by Default',
    description:
      'API keys, tokens, and credentials are automatically redacted from commit annotations. Pre-commit hooks and CI scanning catch secrets before they reach git history.',
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
            className="button button--secondary button--lg"
            href="https://github.com/geneyoo/nocrumbs"
          >
            GitHub
          </Link>
        </div>
      </div>
    </header>
  );
}

function DemoSection() {
  return (
    <section style={{ padding: '2rem 0' }}>
      <div className="container" style={{ textAlign: 'center' }}>
        <img
          src="/img/demo.gif"
          alt="NoCrumbs demo — browse sessions, view diffs"
          style={{
            maxWidth: '100%',
            borderRadius: '8px',
            boxShadow: '0 4px 24px rgba(0, 0, 0, 0.3)',
          }}
        />
      </div>
    </section>
  );
}

function FeaturesSection() {
  return (
    <section className="features">
      <div className="container">
        <div className="row">
          {features.map(({ title, description }, idx) => (
            <div key={idx} className={clsx('col col--3')} style={{ marginBottom: '1.5rem' }}>
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
      <DemoSection />
      <FeaturesSection />
    </Layout>
  );
}
