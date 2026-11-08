import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Optimizr',
  tagline: 'Find the drag. Fix the Mac.',
  favicon: 'img/icon-small.png',

  url: 'https://403access.github.io',
  baseUrl: '/optimizr/docs/',

  organizationName: '403access',
  projectName: 'optimizr',
  trailingSlash: false,

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/403access/optimizr/tree/main/docs-site/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/icon.png',
    colorMode: {
      defaultMode: 'light',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Optimizr Docs',
      logo: {
        alt: 'Optimizr',
        src: 'img/icon-small.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Documentation',
        },
        {
          to: '/roadmap',
          label: 'Roadmap',
          position: 'left',
        },
        {
          href: 'https://403access.github.io/optimizr/',
          label: 'Marketing site',
          position: 'right',
        },
        {
          href: 'https://github.com/403access/optimizr',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Product',
          items: [
            { label: 'Overview', to: '/product/overview' },
            { label: 'Findings catalog', to: '/product/findings-catalog' },
            { label: 'Safety & privacy', to: '/product/safety-and-privacy' },
          ],
        },
        {
          title: 'Engineering',
          items: [
            { label: 'Architecture', to: '/tech/architecture' },
            { label: 'Scanner engine', to: '/tech/scanner-engine' },
            { label: 'Deployment', to: '/tech/deployment' },
          ],
        },
        {
          title: 'Project',
          items: [
            { label: 'Roadmap', to: '/roadmap' },
            { label: 'GitHub', href: 'https://github.com/403access/optimizr' },
            { label: 'Issues', href: 'https://github.com/403access/optimizr/issues' },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Oliver Molnar. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'swift', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
