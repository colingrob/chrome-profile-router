const HOST = 'local.colin.chrome_profile_router';

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: 'choose-profile',
      title: 'Open in a Chrome profile…',
      contexts: ['link'],
      targetUrlPatterns: ['http://*/*', 'https://*/*']
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== 'choose-profile' || !info.linkUrl) return;
  try {
    const response = await chrome.runtime.sendNativeMessage(HOST, {action: 'choose', url: info.linkUrl});
    if (!response?.ok) throw new Error(response?.error || 'Could not open the profile picker.');
    await chrome.action.setBadgeText({text: ''});
  } catch (error) {
    await chrome.action.setBadgeText({text: '!'});
    await chrome.action.setBadgeBackgroundColor({color: '#b45309'});
    await chrome.action.setTitle({title: 'Profile Router: open the toolbar popup to check the companion app.'});
  }
});
