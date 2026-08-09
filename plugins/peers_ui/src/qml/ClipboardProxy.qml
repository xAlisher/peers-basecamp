import QtQuick

// Clipboard access for QML. Qt Quick exposes no clipboard API directly, so the
// standard route is a hidden TextEdit: set the text, select it, copy. Upstream
// logos-chat-ui does the same thing for the same reason.
TextEdit {
    id: proxy
    visible: false
    width: 0
    height: 0

    function copyText(t) {
        if (t === undefined || t === null || String(t).length === 0)
            return false;
        proxy.text = String(t);
        proxy.selectAll();
        proxy.copy();
        proxy.text = "";
        return true;
    }
}
