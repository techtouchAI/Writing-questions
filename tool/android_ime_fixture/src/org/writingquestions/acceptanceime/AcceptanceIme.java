package org.writingquestions.acceptanceime;

import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Test-only real IME. No broadcasts, adb text injection, Flutter test APIs,
 * document seeding or production hooks. Native button taps enter the actual
 * focused editor through Android's InputConnection, including composing state.
 * This is not a claim about Gboard prediction, every layout or human usability.
 */
public final class AcceptanceIme extends InputMethodService {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;

    @Override public boolean onEvaluateFullscreenMode() { return false; }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override public View onCreateInputView() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff5f5f5);
        root.setPadding(dp(4), dp(4), dp(4), dp(4));
        root.setLayoutParams(new ViewGroup.LayoutParams(-1, -2));
        status = new TextView(this);
        status.setTextColor(0xff000000);
        status.setTextSize(12);
        status.setText("Acceptance IME: native InputConnection");
        root.addView(status, new LinearLayout.LayoutParams(-1, dp(24)));
        LinearLayout row = row(root);
        button(row, "IME Arabic", () -> compose("سَ", "سَلَامٌ"));
        button(row, "IME English", () -> compose(" E", " English"));
        button(row, "IME digits", () -> compose(" 1", " 123٤٥٦"));
        row = row(root);
        button(row, "IME select all", this::selectAll);
        button(row, "IME copy", () -> contextAction(android.R.id.copy, "copy"));
        button(row, "IME paste", () -> contextAction(android.R.id.paste, "paste"));
        row = row(root);
        button(row, "IME clear", () -> { selectAll(); commit(""); });
        button(row, "IME multiline", () -> compose("سطر", "سطر أول English ١٢٣\nسطر ثانٍ 456"));
        button(row, "IME end", this::end);
        row = row(root);
        button(row, "IME long", () -> {
            StringBuilder text = new StringBuilder();
            for (int i = 0; i < 320; i++) text.append("سطر عربي English ١٢٣ 456. ");
            text.append("IMETAIL");
            compose("سطر", text.toString());
        });
        button(row, "IME newline", () -> commit("\n"));
        button(row, "IME hide", () -> requestHideSelf(0));
        return root;
    }

    private LinearLayout row(LinearLayout root) {
        LinearLayout row = new LinearLayout(this);
        root.addView(row, new LinearLayout.LayoutParams(-1, dp(48)));
        return row;
    }

    private void button(LinearLayout row, String name, Runnable action) {
        Button button = new Button(this);
        button.setText(name);
        button.setContentDescription(name);
        button.setAllCaps(false);
        button.setTextSize(11);
        button.setPadding(0, 0, 0, 0);
        button.setOnClickListener(view -> {
            try { action.run(); }
            catch (RuntimeException error) { record("error", error.toString(), false); }
        });
        row.addView(button, new LinearLayout.LayoutParams(0, dp(48), 1));
    }

    private InputConnection connection() {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) throw new IllegalStateException("No native InputConnection");
        return connection;
    }

    private ExtractedText extracted() {
        ExtractedText text = connection().getExtractedText(new ExtractedTextRequest(), 0);
        if (text == null || text.text == null) throw new IllegalStateException("Editor did not expose extracted text");
        return text;
    }

    private void selectAll() {
        ExtractedText text = extracted();
        record("setSelection", "all", connection().setSelection(text.startOffset, text.startOffset + text.text.length()));
    }

    private void end() {
        ExtractedText text = extracted();
        int end = text.startOffset + text.text.length();
        record("setSelection", "end", connection().setSelection(end, end));
    }

    private void compose(String first, String complete) {
        final InputConnection original = connection();
        record("setComposingText", first, original.setComposingText(first, 1));
        handler.postDelayed(() -> {
            // Do not commit into an unrelated field after a focus transition.
            if (getCurrentInputConnection() != original) {
                record("focus changed during composition", complete, false);
                return;
            }
            record("setComposingText", complete, original.setComposingText(complete, 1));
            record("commitText", complete, original.commitText(complete, 1));
            record("finishComposingText", complete, original.finishComposingText());
        }, 250);
    }

    private void commit(String text) { record("commitText", text, connection().commitText(text, 1)); }
    private void contextAction(int action, String name) {
        record(name, "", connection().performContextMenuAction(action));
    }

    private void record(String operation, String input, boolean accepted) {
        try {
            JSONObject event = new JSONObject();
            event.put("operation", operation);
            event.put("input", input);
            event.put("accepted", accepted);
            event.put("package", getCurrentInputEditorInfo() == null ? "" : getCurrentInputEditorInfo().packageName);
            ExtractedText current = getCurrentInputConnection() == null ? null : getCurrentInputConnection().getExtractedText(new ExtractedTextRequest(), 0);
            if (current != null) {
                event.put("editorText", current.text);
                event.put("selectionStart", current.selectionStart);
                event.put("selectionEnd", current.selectionEnd);
            }
            try (FileOutputStream stream = new FileOutputStream(new File(getFilesDir(), "events.jsonl"), true)) {
                stream.write((event.toString() + "\n").getBytes(StandardCharsets.UTF_8));
            }
            if (status != null) status.setText("IME " + operation + ": " + accepted);
        } catch (Exception error) {
            if (status != null) status.setText("IME evidence error: " + error);
            throw new IllegalStateException(error);
        }
    }
}
