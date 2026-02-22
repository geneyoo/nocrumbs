import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

const features = [
  {
    title: 'Local-First, Always',
    description:
      'Your AI context never leaves your machine. No cloud sync, no telemetry, no third-party servers. NoCrumbs works entirely on your local filesystem.',
  },
  {
    title: 'Git-Native',
    description:
      'Hooks into your existing git workflow. NoCrumbs watches for changes and automatically strips AI breadcrumbs from your commits before they hit the repo.',
  },
  {
    title: 'CLI + Mac App',
    description:
      'Use the CLI for automation and scripting, or the native macOS app for a visual overview. Both share the same engine.',
  },
];

function HeroSection() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className="hero hero--primary">
      <div className="container" style={{ textAlign: 'center' }}>
        <h1 className="hero__title">{siteConfig.title}</h1>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', marginTop: '2rem' }}>
          <Link className="button button--primary button--lg" to="/docs/getting-started">
            Get Started
          </Link>
          <Link
            className="button button--secondary button--lg"
            href="https://github.com/pdswan/nocrumbs"
          >
            GitHub
          </Link>
        </div>
        <div className="install-hint">
          <code>brew install nocrumbs</code>
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
