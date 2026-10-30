package org.writingquestions.acceptanceautomation;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Xml;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.io.StringWriter;
import java.util.List;
import org.xmlpull.v1.XmlSerializer;

/** Read-only native window observer. No text, document or clipboard injection.
 * Unlike the uiautomator CLI's active-app root, getWindows includes the actual
 * InputMethod window. A separate process never restarts the editor or keyboard.
 */
public final class WindowDump extends Instrumentation {
    private int count;
    @Override public void onCreate(Bundle args) { super.onCreate(args); start(); }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            UiAutomation automation = getUiAutomation();
            AccessibilityServiceInfo info = automation.getServiceInfo();
            info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                    | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                    | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            automation.setServiceInfo(info);
            automation.waitForIdle(100, 5000);
            StringWriter text = new StringWriter();
            XmlSerializer xml = Xml.newSerializer();
            xml.setOutput(text); xml.startDocument("UTF-8", true);
            xml.startTag(null, "hierarchy");
            List<AccessibilityWindowInfo> windows = automation.getWindows();
            if (windows.isEmpty()) throw new IllegalStateException("No interactive Android windows");
            for (AccessibilityWindowInfo window : windows) {
                AccessibilityNodeInfo root = window.getRoot();
                if (root != null) { node(xml, root, 0); root.recycle(); }
            }
            xml.endTag(null, "hierarchy"); xml.endDocument();
            if (count == 0) throw new IllegalStateException("No visible native nodes");
            result.putString("xml", text.toString());
            finish(0, result);
        } catch (Exception error) {
            result.putString("error", error.toString());
            finish(1, result);
        }
    }

    private void node(XmlSerializer xml, AccessibilityNodeInfo node, int depth) throws Exception {
        if (!node.isVisibleToUser()) return;
        if (depth > 80 || ++count > 2000) throw new IllegalStateException("Window hierarchy exceeds audited limits; refusing truncation");
        Rect rect = new Rect(); node.getBoundsInScreen(rect);
        xml.startTag(null, "node");
        attribute(xml, "text", node.getText());
        attribute(xml, "content-desc", node.getContentDescription());
        attribute(xml, "class", node.getClassName());
        attribute(xml, "package", node.getPackageName());
        attribute(xml, "resource-id", node.getViewIdResourceName());
        attribute(xml, "bounds", "["+rect.left+","+rect.top+"]["+rect.right+","+rect.bottom+"]");
        attribute(xml, "clickable", Boolean.toString(node.isClickable()));
        attribute(xml, "enabled", Boolean.toString(node.isEnabled()));
        attribute(xml, "focused", Boolean.toString(node.isFocused()));
        attribute(xml, "focusable", Boolean.toString(node.isFocusable()));
        attribute(xml, "scrollable", Boolean.toString(node.isScrollable()));
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child != null) { node(xml, child, depth+1); child.recycle(); }
        }
        xml.endTag(null, "node");
    }
    private void attribute(XmlSerializer xml, String name, CharSequence value) throws Exception {
        xml.attribute(null, name, value == null ? "" : value.toString());
    }
}
