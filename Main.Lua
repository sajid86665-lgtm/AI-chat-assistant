require "import"
import "android.widget.*"
import "android.view.*"
import "android.graphics.*"
import "android.content.Context"
import "android.content.Intent"
import "android.speech.RecognizerIntent"
import "com.androlua.Http"
import "android.app.AlertDialog"
import "java.util.ArrayList"
import "android.content.SharedPreferences"
import "android.media.MediaPlayer"
import "android.widget.AdapterView"
import "android.widget.ArrayAdapter"
import "android.widget.ListView"
import "android.widget.Toast"
import "java.text.SimpleDateFormat"
import "java.util.Date"
import "java.util.Locale"
import "android.os.Handler"
import "android.os.Looper"
import "android.net.Uri"
import "cjson"

-- 1. GLOBAL CONFIG
local app_name = "AI Chat Assistant"
local platform = "Jieshuo Screen Reader"
local config = { currentProvider = "Groq" }

-- 2. API KEY MANAGEMENT
local PREFS_NAME = "AIChatPrefs"
local prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

function getGroqApiKey() return prefs.getString("groq_api_key", "") end
function saveGroqApiKey(key) prefs.edit().putString("groq_api_key", key).commit() end
function getGroqModel() return prefs.getString("groq_model", "llama-3.1-8b-instant") end
function saveGroqModel(model) prefs.edit().putString("groq_model", model).commit() end
function getOpenRouterKey() return prefs.getString("openrouter_key", "") end
function saveOpenRouterKey(key) prefs.edit().putString("openrouter_key", key).commit() end
function getOpenRouterModel() return prefs.getString("openrouter_model", "google/gemini-2.0-flash-001") end
function saveOpenRouterModel(model) prefs.edit().putString("openrouter_model", model).commit() end
function getCurrentProvider() return prefs.getString("current_provider", "Groq") end
function saveCurrentProvider(provider) prefs.edit().putString("current_provider", provider).commit() config.currentProvider = provider end

-- 3. MAIN UI
local main_layout = {
  LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", backgroundColor="#ffffff",
  {
    LinearLayout, layout_width="fill", layout_height="60dp", backgroundColor="#1A1A1A", gravity="center_vertical",
    { TextView, text=app_name, textColor=0xffffffff, textSize="18sp", layout_weight=1, paddingLeft="15dp" },
    { Button, id="more_btn", text="More", backgroundColor="#333333", textColor=0xffffffff },
  },
  { ListView, id="chat_window", layout_width="fill", layout_height="fill", layout_weight=1 },
  { 
    LinearLayout, layout_width="fill", padding="10dp", backgroundColor="#eeeeee", gravity="center_vertical",
    { EditText, id="user_input", hint="Ask AI...", layout_weight=1 },
    { Button, id="send_btn", text="SEND", textColor=0xff2196F3 },
    { Button, id="voice_btn", text="Voice", textColor=0xff2196F3 },
  }
}

activity.setContentView(loadlayout(main_layout))
local chat_data = ArrayList()
local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, chat_data)
chat_window.setAdapter(adapter)

-- 4. DIALOGS
function showMoreOptions()
    local dlg = AlertDialog.Builder(activity)
    dlg.setItems({"API Settings", "About"}, function(dialog, which)
        if which == 0 then openAPISettings() elseif which == 1 then showAbout() end
    end)
    dlg.show()
end

function showAbout()
    local dlg = AlertDialog.Builder(activity)
    dlg.setTitle("About")
    dlg.setMessage("AI Chat Assistant v2.0\nDeveloper: Mezab Ali\nOptimized for Jieshuo.")
    dlg.show()
end

function openAPISettings()
    local set_layout = LinearLayout(activity)
    set_layout.setOrientation(LinearLayout.VERTICAL)
    set_layout.setPadding(40, 40, 40, 40)
    local providerSpinner = Spinner(activity)
    local providers = {"Groq", "OpenRouter"}
    providerSpinner.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_item, providers))
    set_layout.addView(providerSpinner)
    local dynamicContainer = LinearLayout(activity)
    dynamicContainer.setOrientation(LinearLayout.VERTICAL)
    set_layout.addView(dynamicContainer)

    local groqModels = {"llama-3.1-8b-instant", "llama-3.3-70b-versatile", "mixtral-8x7b-32768", "gemma2-9b-it"}
    local orModels = {"google/gemini-2.0-flash-001", "google/gemini-2.5-pro-exp-03-25", "anthropic/claude-3.7-sonnet"}

    function createFields(isGroq)
        dynamicContainer.removeAllViews()
        local input = EditText(activity)
        input.setId(1001)
        input.setHint(isGroq and "Enter Groq API Key" or "Enter OpenRouter API Key")
        input.setText(isGroq and getGroqApiKey() or getOpenRouterKey())
        dynamicContainer.addView(input)
        local spin = Spinner(activity)
        spin.setId(1002)
        spin.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_item, isGroq and groqModels or orModels))
        dynamicContainer.addView(spin)
    end
    providerSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener {
        onItemSelected = function(p, v, pos) createFields(providers[pos+1] == "Groq") end,
        onNothingSelected = function() end
    })
    local dlg = AlertDialog.Builder(activity)
    dlg.setView(set_layout)
    dlg.setPositiveButton("SAVE", function()
        local prov = providers[providerSpinner.getSelectedItemPosition() + 1]
        saveCurrentProvider(prov)
        local input = set_layout.findViewById(1001)
        local spin = set_layout.findViewById(1002)
        local val = tostring(input.getText())
        local model = (prov == "Groq" and groqModels or orModels)[spin.getSelectedItemPosition() + 1]
        if prov == "Groq" then saveGroqApiKey(val) saveGroqModel(model)
        else saveOpenRouterKey(val) saveOpenRouterModel(model) end
        Toast.makeText(activity, "Saved!", Toast.LENGTH_SHORT).show()
    end)
    dlg.show()
end

-- 5. AI FETCH
function fetchAI(query)
    local idx = chat_data.size()
    chat_data.add("AI. Thinking...")
    adapter.notifyDataSetChanged()
    local isGroq = (getCurrentProvider() == "Groq")
    local key = isGroq and getGroqApiKey() or getOpenRouterKey()
    local url = isGroq and "https://api.groq.com/openai/v1/chat/completions" or "https://openrouter.ai/api/v1/chat/completions"
    local model = isGroq and getGroqModel() or getOpenRouterModel()
    local post_body = '{"model": "'..model..'", "messages": [{"role": "user", "content": "'..query..'"}], "max_tokens": 4096}'
    Http.post(url, post_body, {["Authorization"] = "Bearer "..key, ["Content-Type"] = "application/json"}, function(code, res)
        if code == 200 then
            local decoded = cjson.decode(res)
            chat_data.set(idx, "AI. "..decoded.choices[1].message.content)
        else
            chat_data.set(idx, "AI. Error: "..code)
        end
        adapter.notifyDataSetChanged()
    end)
end

-- 6. VOICE
function startVoiceRecognition()
    local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
    activity.startActivityForResult(intent, 101)
end

function onActivityResult(requestCode, resultCode, data)
    if requestCode == 101 and resultCode == activity.RESULT_OK then
        local res = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
        if res and res.size() > 0 then
            local spoken = tostring(res.get(0))
            chat_data.add("Me. "..spoken)
            adapter.notifyDataSetChanged()
            fetchAI(spoken)
        end
    end
end

-- 7. LISTENERS
more_btn.onClick = function() showMoreOptions() end
send_btn.onClick = function()
    local t = tostring(user_input.getText())
    if t ~= "" then chat_data.add("Me. "..t) fetchAI(t) user_input.setText("") end
end
voice_btn.onClick = function() startVoiceRecognition() end
chat_window.setOnItemLongClickListener(AdapterView.OnItemLongClickListener {
    onItemLongClick = function(p, v, pos) chat_data.remove(pos) adapter.notifyDataSetChanged() return true end
})