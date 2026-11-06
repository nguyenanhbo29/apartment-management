const nodemailer = require('nodemailer');
const env = require('../config/env');

let transporter;
function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: env.mail.host,
      port: env.mail.port,
      secure: env.mail.port === 465,
      auth: { user: env.mail.user, pass: env.mail.pass },
    });
  }
  return transporter;
}

const isConsoleMode = () => env.mail.mode !== 'smtp';

async function sendMail({ to, subject, text }) {
  if (isConsoleMode()) {
    if (env.nodeEnv !== 'test') console.log(`[mail:console] to=${to} | ${subject}\n${text}`);
    return;
  }
  await getTransporter().sendMail({ from: env.mail.from, to, subject, text });
}

module.exports = { sendMail, isConsoleMode };
