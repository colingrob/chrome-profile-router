const HOST = 'local.colin.chrome_profile_router';
const status = document.querySelector('#status');
const choose = document.querySelector('#choose');
const settings = document.querySelector('#settings');
let currentURL;

async function send(message) {
  const response = await chrome.runtime.sendNativeMessage(HOST, message);
  if (!response?.ok) throw new Error(response?.error || 'The companion could not open this request.');
  return response;
}

function showError(error) {
  status.className = 'error';
  status.textContent = error.message.includes('native messaging host') || error.message.includes('Native host')
    ? 'Install the macOS companion with scripts/install.sh, then reopen this popup.'
    : error.message;
}

choose.addEventListener('click', async () => {
  choose.disabled = true;
  try { await send({action: 'choose', url: currentURL}); window.close(); }
  catch (error) { showError(error); choose.disabled = false; }
});
settings.addEventListener('click', async () => {
  try { await send({action: 'settings'}); window.close(); }
  catch (error) { showError(error); }
});

(async () => {
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    if (tab?.url && /^https?:\/\//i.test(tab.url)) {
      currentURL = tab.url;
      document.querySelector('#site').textContent = new URL(currentURL).host;
    } else { document.querySelector('#site').textContent = 'Open a web page to choose its profile'; }
    await send({action: 'ping'});
    choose.disabled = !currentURL;
    settings.disabled = false;
    status.textContent = 'Connected. Choices are shared across your profiles.';
    await chrome.action.setBadgeText({text: ''});
    await chrome.action.setTitle({title: 'Choose a Chrome profile'});
  } catch (error) { showError(error); }
})();
