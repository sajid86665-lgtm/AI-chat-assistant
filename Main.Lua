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
import "java.io.File"
import "cjson"

-- Paths
local SEND_SOUND = "/storage/emulated/0/解说/Tools/AI chat assistant/A.I Sounds/Send.wav"
local RECEIVE_SOUND = "/storage/emulated/0/解说/Tools/AI chat assistant/A.I Sounds/Receive.wav"

-- Sound Player Function
function playSound(path)
    if File(path).exists() then
        local mp = MediaPlayer()
        mp.setDataSource(path)
        mp.prepare()
        mp.start()
        mp.setOnCompletionListener({onCompletion=function(m) m.release() end})
    end
end

-- 1. CONFIG & PREFS
local app_name = "AI Chat Assistant"
local prefs = activity.getSharedPreferences("AIChatPrefs", Context.MODE_PRIVATE)

function getGroqApiKey() return prefs.getString("groq_api_key", "") end
function getGroqModel() return prefs.getString("groq_model", "llama-3.1-8b-instant") end
function getOpenRouterKey() return prefs.getString("openrouter_key", "") end
function getOpenRouterModel() return prefs.getString("openrouter_model", "google/gemini-2.0-flash-001") end
function getCurrentProvider() return prefs.getString("current_provider", "Groq") end

-- 2. UI
local main_layout = {
  LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", backgroundColor="#ffffff",
  { LinearLayout, layout_width="fill", layout_height="60dp", backgroundColor="#1A1A1A", gravity="center_vertical",
    { TextView, text=app_name, textColor=0xffffffff, textSize="18sp", layout_weight=1, paddingLeft="15dp" },
    { Button, id="more_btn", text="More", backgroundColor="#333333", textColor=0xffffffff },
  },
  { ListView, id="chat_window", layout_width="fill", layout_height="fill", layout_weight=1 },
  { LinearLayout, layout_width="fill", padding="10dp", backgroundColor="#eeeeee", gravity="center_vertical",
    { EditText, id="user_input", hint="Ask AI...", layout_weight=1 },
    { Button, id="send_btn", text="SEND", textColor=0xff2196F3 },
    { Button, id="voice_btn", text="Voice", textColor=0xff2196F3 },
  }
}

activity.setContentView(loadlayout(main_layout))
local chat_data = ArrayList()
local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, chat_data)
chat_window.setAdapter(adapter)

-- 3. AI FETCH (With Sound)
function fetchAI(query)
    local idx = chat_data.size()
    chat_data.add("AI. Thinking...")
    adapter.notifyDataSetChanged()
    playSound(SEND_SOUND) -- SEND SOUND
    
    local isGroq = (getCurrentProvider() == "Groq")
    local key = isGroq and getGroqApiKey() or getOpenRouterKey()
    local url = isGroq and "https://api.groq.com/openai/v1/chat/completions" or "https://openrouter.ai/api/v1/chat/completions"
    local model = isGroq and getGroqModel() or getOpenRouterModel()
    
    local post_body = '{"model": "'..model..'", "messages": [{"role": "user", "content": "'..query..'"}], "max_tokens": 4096}'
    Http.post(url, post_body, {["Authorization"] = "Bearer "..key, ["Content-Type"] = "application/json"}, function(code, res)
        if code == 200 then
            local decoded = cjson.decode(res)
            chat_data.set(idx, "AI. "..decoded.choices[1].message.content)
            playSound(RECEIVE_SOUND) -- RECEIVE SOUND
        else
            chat_data.set(idx, "AI. Error: "..code)
        end
        adapter.notifyDataSetChanged()
    end)
end

-- 4. VOICE & LISTENERS
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

more_btn.onClick = function() 
    local dlg = AlertDialog.Builder(activity)
    dlg.setItems({"API Settings", "About"}, function(d, w) 
        if w == 0 then -- Add your existing openAPISettings function here
        else Toast.makeText(activity, "Version 2.0", 0).show() end 
    end)
    dlg.show()
end

send_btn.onClick = function()
    local t = tostring(user_input.getText())
    if t ~= "" then chat_data.add("Me. "..t) fetchAI(t) user_input.setText("") end
end

voice_btn.onClick = function() startVoiceRecognition() end
