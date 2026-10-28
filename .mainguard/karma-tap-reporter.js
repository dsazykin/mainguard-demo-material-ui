'use strict';
// W7c: a karma reporter that writes one TAP line per spec to the file in MG_KARMA_TAP, so Mainguard reads the browser tests by name.
// Karma's own output (dots) stays on standard output and standard error; suite.sh prints this file after the run, with "[karma] " in
// front of every name so a browser test is never confused with the jsdom unit test of the same title.
const fs = require('fs');

function MgTapReporter(baseReporterDecorator) {
  baseReporterDecorator(this);
  const lines = [];
  let n = 0;
  // the dots reporter's chatter is not wanted, only the TAP file
  this.onSpecComplete = (browser, result) => {
    n += 1;
    const name = [...(result.suite || []), result.description].join(' ').replace(/\s+/g, ' ').trim();
    if (result.skipped) lines.push(`ok ${n} ${name} # SKIP`);
    else if (result.success) lines.push(`ok ${n} ${name}`);
    else lines.push(`not ok ${n} ${name}`);
  };
  // mocha's closing summary, only for a run that ended (no karma error, no browser lost): what tells quarantine.js the run reached
  // its end (PD-79)
  this.onRunComplete = (browsers, results) => {
    const tail = results && (results.error || results.disconnected) ? [] : [`# fail ${lines.filter((l) => l.startsWith('not ok ')).length}`];
    if (process.env.MG_KARMA_TAP) fs.writeFileSync(process.env.MG_KARMA_TAP, `${lines.concat(tail).join('\n')}\n`);
  };
}
MgTapReporter.$inject = ['baseReporterDecorator'];

module.exports = { 'reporter:mg-tap': ['type', MgTapReporter] };
