/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'getting-started',
    'how-it-works',
    {
      type: 'category',
      label: 'Guides',
      items: ['guides/cli-usage', 'guides/app-usage'],
    },
    'contributing',
    'faq',
  ],
};

module.exports = sidebars;
