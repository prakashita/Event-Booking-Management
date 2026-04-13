const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();

  page.on('console', (msg) => {
    console.log('PAGE LOG:', msg.type(), msg.text());
  });

  page.on('pageerror', (err) => {
    console.log('PAGE ERROR:', err.message);
  });

  page.on('requestfailed', (request) => {
    console.log(`REQUEST FAILED: ${request.url()} ${request.failure()?.errorText}`);
  });

  await page.goto('http://127.0.0.1:5173/');
  await page.waitForTimeout(3000);

  const html = await page.content();
  console.log('PAGE HTML SNIPPET:', html.slice(0, 800));
  await browser.close();
})();
