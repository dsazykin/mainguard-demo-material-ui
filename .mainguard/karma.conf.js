'use strict';
// W7c: the repository's own karma configuration (test/karma.conf.js, what `yarn test:karma` runs in its CI), with three changes:
// the reporter (karma-tap-reporter.js, so Mainguard reads every spec by name), a single run, and Chrome only (its CI also runs
// Firefox and BrowserStack, which need a network and a key). The browser binary comes from PLAYWRIGHT_BROWSERS_PATH (suite.sh points
// it at the image's Chrome, because the Playwright browsers of the benchmark's image sit in /root, out of the jail user's reach).
const base = require('../test/karma.conf.js');

module.exports = function setKarmaConfig(config) {
  base(config);
  const next = {
    reporters: ['mg-tap'],
    plugins: [...(config.plugins || []), require('./karma-tap-reporter.js')],
    singleRun: true,
  };
  if (config.customLaunchers && config.customLaunchers.chromeHeadless) {
    next.browsers = ['chromeHeadless'];
    next.customLaunchers = {
      ...config.customLaunchers,
      chromeHeadless: {
        ...config.customLaunchers.chromeHeadless,
        flags: [...config.customLaunchers.chromeHeadless.flags, '--disable-gpu', '--disable-dev-shm-usage'],
      },
    };
  } else if ((config.browsers || []).includes('ChromeHeadless')) {
    // The 2018 bases launch plain ChromeHeadless (puppeteer's Chromium): it cannot start as root (the benchmark's image) and has no
    // sandbox in a container (the jails), so it never started and karma ran nothing, in every place. The launcher the later bases
    // define for themselves (ChromeHeadlessNoSandbox) is given to them.
    next.browsers = config.browsers.map((b) => (b === 'ChromeHeadless' ? 'mgChromeHeadless' : b));
    next.customLaunchers = {
      ...config.customLaunchers,
      mgChromeHeadless: { base: 'ChromeHeadless', flags: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'] },
    };
  }
  config.set(next);
};
