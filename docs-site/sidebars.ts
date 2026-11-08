import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Product',
      collapsed: false,
      items: [
        'product/overview',
        'product/findings-catalog',
        'product/safety-and-privacy',
        'product/faq',
      ],
    },
    {
      type: 'category',
      label: 'Engineering',
      collapsed: false,
      items: [
        'tech/architecture',
        'tech/scanner-engine',
        'tech/data-model',
        'tech/build-and-run',
        'tech/testing',
        'tech/deployment',
        'tech/contributing',
      ],
    },
    'roadmap',
  ],
};

export default sidebars;
