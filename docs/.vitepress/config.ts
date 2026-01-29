import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'pad',
  description: 'cognitive stdin sink',
  base: '/pad/',
  themeConfig: {
    nav: [
      { text: 'Guide', link: '/' },
      { text: 'API', link: '/api' },
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'CLI Reference', link: '/cli' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'HTTP API', link: '/api' },
          { text: 'Architecture', link: '/architecture' },
        ],
      },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/pterror/pad' },
    ],
  },
})
