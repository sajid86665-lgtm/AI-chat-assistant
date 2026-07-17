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

local config = {
  currentProvider = "Groq"
}

-- Sound paths
local SEND_SOUND = "/storage/emulated/0/解说/Tools/AI chat assistant/A.I Sounds/Send.wav"
local RECEIVE_SOUND = "/storage/emulated/0/解说/Tools/AI chat assistant/A.I Sounds/Receive.wav"

-- Handler for delays
local handler = Handler(Looper.getMainLooper())
local isVoiceRecording = false

-- Toast function
function showToast(msg)
    Toast.makeText(activity, msg, Toast.LENGTH_SHORT).show()
end

-- Time function
function getCurrentTime()
    local date = Date()
    local format = SimpleDateFormat("h:mm a", Locale.US)
    return format.format(date)
end

-- 2. API KEY MANAGEMENT
local PREFS_NAME = "AIChatPrefs"
local prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
local editor = prefs.edit()

function getGroqApiKey()
    return prefs.getString("groq_api_key", "")
end

function saveGroqApiKey(key)
    editor.putString("groq_api_key", key)
    editor.commit()
end

function getGroqModel()
    return prefs.getString("groq_model", "llama-3.1-8b-instant")
end

function saveGroqModel(model)
    editor.putString("groq_model", model)
    editor.commit()
end

function getOpenRouterKey()
    return prefs.getString("openrouter_key", "")
end

function saveOpenRouterKey(key)
    editor.putString("openrouter_key", key)
    editor.commit()
end

function getOpenRouterModel()
    return prefs.getString("openrouter_model", "google/gemini-2.0-flash-001")
end

function saveOpenRouterModel(model)
    editor.putString("openrouter_model", model)
    editor.commit()
end

function getCurrentProvider()
    return prefs.getString("current_provider", "Groq")
end

function saveCurrentProvider(provider)
    editor.putString("current_provider", provider)
    editor.commit()
    config.currentProvider = provider
end

-- 3. SOUND PLAYER (Always ON with 100% volume)
function playSound(soundPath)
    if not soundPath or soundPath == "" then 
        return 
    end
    
    local file = io.open(soundPath, "r")
    if not file then 
        print("Sound file not found: " .. soundPath)
        return 
    end
    file:close()
    
    local player = MediaPlayer()
    player.setDataSource(soundPath)
    player.prepare()
    player.setVolume(1.0, 1.0)
    player.start()
    player.setOnCompletionListener(MediaPlayer.OnCompletionListener {
        onCompletion = function(mp)
            mp.release()
        end
    })
end

-- 4. MAIN UI
local main_layout = {
  LinearLayout,
  orientation="vertical",
  layout_width="fill",
  layout_height="fill",
  backgroundColor="#ffffff",
  {
    LinearLayout, 
    layout_width="fill",
    layout_height="60dp",
    backgroundColor="#1A1A1A",
    gravity="center_vertical",
    paddingLeft="15dp",
    paddingRight="10dp",
    { TextView, text=app_name, textColor=0xffffffff, textSize="18sp", layout_weight=1 },
    { Button, id="more_btn", text="More Options", backgroundColor="#333333", textColor=0xffffffff, textSize="12sp" },
  },
  { ListView, id="chat_window", layout_width="fill", layout_height="fill", layout_weight=1, dividerHeight="0dp" },
  { 
    LinearLayout, 
    layout_width="fill", padding="10dp", backgroundColor="#eeeeee",
    gravity="center_vertical",
    { EditText, id="user_input", hint="Ask AI...", layout_weight=1 },
    { Button, id="send_btn", text="SEND", textColor=0xff2196F3, backgroundColor="#00000000" },
    { Button, id="voice_btn", text="Voice Message", layout_width="wrap", backgroundColor="#00000000", textSize="12sp" },
  }
}

activity.setContentView(loadlayout(main_layout))
local chat_data = ArrayList()
local adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, chat_data)
chat_window.setAdapter(adapter)

-- 5. MORE OPTIONS DIALOG
function showMoreOptions()
    local dlg = AlertDialog.Builder(activity)
    local options = {
        "API Settings",
        "About"
    }
    
    dlg.setTitle("More Options")
    dlg.setItems(options, function(dialog, which)
        if which == 0 then
            openAPISettings()
        elseif which == 1 then
            showAbout()
        end
    end)
    dlg.show()
end

-- 6. ABOUT DIALOG (No Close Button)
function showAbout()
    local dlg = AlertDialog.Builder(activity)
    local about_layout = LinearLayout(activity)
    about_layout.setOrientation(LinearLayout.VERTICAL)
    about_layout.setPadding(25, 20, 25, 20)
    about_layout.setBackgroundColor(0xFFFFFFFF)
    
    local scrollView = ScrollView(activity)
    scrollView.setLayoutParams(LinearLayout.LayoutParams(-1, 500))
    
    local contentLayout = LinearLayout(activity)
    contentLayout.setOrientation(LinearLayout.VERTICAL)
    contentLayout.setPadding(10, 5, 10, 5)
    
    -- App Title
    local title = TextView(activity)
    title.setText("AI Chat Assistant")
    title.setTextSize(22)
    title.setTextColor(0xFF1A1A1A)
    title.setGravity(Gravity.CENTER)
    title.setTypeface(Typeface.DEFAULT_BOLD)
    title.setPadding(0, 0, 0, 5)
    contentLayout.addView(title)
    
    local version = TextView(activity)
    version.setText("Version 2.0")
    version.setTextSize(14)
    version.setTextColor(0xFF666666)
    version.setGravity(Gravity.CENTER)
    version.setPadding(0, 0, 0, 5)
    contentLayout.addView(version)
    
    local platformText = TextView(activity)
    platformText.setText("Platform: " .. platform)
    platformText.setTextSize(13)
    platformText.setTextColor(0xFF888888)
    platformText.setGravity(Gravity.CENTER)
    platformText.setPadding(0, 0, 0, 15)
    contentLayout.addView(platformText)
    
    local divider1 = View(activity)
    divider1.setBackgroundColor(0xFFDDDDDD)
    divider1.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider1.setPadding(0, 5, 0, 10)
    contentLayout.addView(divider1)
    
    -- Developer Section
    local devLabel = TextView(activity)
    devLabel.setText("Developer")
    devLabel.setTextSize(16)
    devLabel.setTextColor(0xFF1A1A1A)
    devLabel.setTypeface(Typeface.DEFAULT_BOLD)
    devLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(devLabel)
    
    local devName = TextView(activity)
    devName.setText("Mezab Ali")
    devName.setTextSize(14)
    devName.setTextColor(0xFF333333)
    devName.setPadding(0, 0, 0, 10)
    contentLayout.addView(devName)
    
    local divider2 = View(activity)
    divider2.setBackgroundColor(0xFFDDDDDD)
    divider2.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider2.setPadding(0, 5, 0, 10)
    contentLayout.addView(divider2)
    
    -- About App Section
    local aboutLabel = TextView(activity)
    aboutLabel.setText("About This App")
    aboutLabel.setTextSize(16)
    aboutLabel.setTextColor(0xFF1A1A1A)
    aboutLabel.setTypeface(Typeface.DEFAULT_BOLD)
    aboutLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(aboutLabel)
    
    local aboutText = TextView(activity)
    aboutText.setText("AI Chat Assistant is a powerful Android application that allows you to chat with advanced AI models. The app supports multiple AI providers including Groq and OpenRouter, giving you flexibility to choose the best AI model for your needs.")
    aboutText.setTextSize(13)
    aboutText.setTextColor(0xFF444444)
    aboutText.setPadding(0, 0, 0, 10)
    aboutText.setLineSpacing(1.2, 1.2)
    contentLayout.addView(aboutText)
    
    local divider3 = View(activity)
    divider3.setBackgroundColor(0xFFDDDDDD)
    divider3.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider3.setPadding(0, 5, 0, 10)
    contentLayout.addView(divider3)
    
    -- Features Section
    local featuresLabel = TextView(activity)
    featuresLabel.setText("Key Features")
    featuresLabel.setTextSize(16)
    featuresLabel.setTextColor(0xFF1A1A1A)
    featuresLabel.setTypeface(Typeface.DEFAULT_BOLD)
    featuresLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(featuresLabel)
    
    local features = {
        "• Multiple AI Providers (Groq & OpenRouter)",
        "• Voice Message Support (Hold to Record)",
        "• Real-time Chat with Timestamps",
        "• Copy, Share & Delete Messages",
        "• Automatic Sound Feedback",
        "• Optimized for Jieshuo Screen Reader"
    }
    
    for i, feature in ipairs(features) do
        local fText = TextView(activity)
        fText.setText(feature)
        fText.setTextSize(13)
        fText.setTextColor(0xFF444444)
        fText.setPadding(5, 2, 0, 2)
        contentLayout.addView(fText)
    end
    
    local divider4 = View(activity)
    divider4.setBackgroundColor(0xFFDDDDDD)
    divider4.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider4.setPadding(0, 10, 0, 10)
    contentLayout.addView(divider4)
    
    -- Supported Models Section
    local modelsLabel = TextView(activity)
    modelsLabel.setText("Supported AI Models")
    modelsLabel.setTextSize(16)
    modelsLabel.setTextColor(0xFF1A1A1A)
    modelsLabel.setTypeface(Typeface.DEFAULT_BOLD)
    modelsLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(modelsLabel)
    
    local models = {
        "Groq Models:",
        "  • Llama 3.1 8B Instant",
        "  • Llama 3.3 70B Versatile",
        "  • Mixtral 8x7B",
        "  • Gemma 2 9B IT",
        "",
        "OpenRouter Models:",
        "  • Gemini 2.0 Flash",
        "  • Gemini 2.5 Pro",
        "  • Claude 3.7 Sonnet"
    }
    
    for i, model in ipairs(models) do
        local mText = TextView(activity)
        mText.setText(model)
        mText.setTextSize(13)
        mText.setTextColor(0xFF444444)
        mText.setPadding(5, 2, 0, 2)
        if model:match(":$") then
            mText.setTypeface(Typeface.DEFAULT_BOLD)
            mText.setTextColor(0xFF333333)
        end
        contentLayout.addView(mText)
    end
    
    local divider5 = View(activity)
    divider5.setBackgroundColor(0xFFDDDDDD)
    divider5.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider5.setPadding(0, 10, 0, 10)
    contentLayout.addView(divider5)
    
    -- How to Use Section
    local usageLabel = TextView(activity)
    usageLabel.setText("How to Use")
    usageLabel.setTextSize(16)
    usageLabel.setTextColor(0xFF1A1A1A)
    usageLabel.setTypeface(Typeface.DEFAULT_BOLD)
    usageLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(usageLabel)
    
    local usage = {
        "1. Go to More Options → API Settings",
        "2. Select your preferred AI Provider",
        "3. Enter your API Key",
        "4. Select the AI Model",
        "5. Start chatting by typing or using voice",
        "",
        "Tip: Hold the 'Voice Message' button to record your voice."
    }
    
    for i, step in ipairs(usage) do
        local uText = TextView(activity)
        uText.setText(step)
        uText.setTextSize(13)
        uText.setTextColor(0xFF444444)
        uText.setPadding(5, 2, 0, 2)
        contentLayout.addView(uText)
    end
    
    local divider6 = View(activity)
    divider6.setBackgroundColor(0xFFDDDDDD)
    divider6.setLayoutParams(LinearLayout.LayoutParams(-1, 2))
    divider6.setPadding(0, 10, 0, 10)
    contentLayout.addView(divider6)
    
    -- App Info
    local infoLabel = TextView(activity)
    infoLabel.setText("App Information")
    infoLabel.setTextSize(16)
    infoLabel.setTextColor(0xFF1A1A1A)
    infoLabel.setTypeface(Typeface.DEFAULT_BOLD)
    infoLabel.setPadding(0, 5, 0, 5)
    contentLayout.addView(infoLabel)
    
    local infoItems = {
        "• Platform: " .. platform,
        "• Language: Lua (AndroLua)",
        "• API: Groq & OpenRouter",
        "• Last Updated: July 2026",
        "• Free to Use"
    }
    
    for i, info in ipairs(infoItems) do
        local iText = TextView(activity)
        iText.setText(info)
        iText.setTextSize(13)
        iText.setTextColor(0xFF444444)
        iText.setPadding(5, 2, 0, 2)
        contentLayout.addView(iText)
    end
    
    scrollView.addView(contentLayout)
    about_layout.addView(scrollView)
    
    local socialLabel = TextView(activity)
    socialLabel.setText("Connect with Us")
    socialLabel.setTextSize(16)
    socialLabel.setTextColor(0xFF1A1A1A)
    socialLabel.setTypeface(Typeface.DEFAULT_BOLD)
    socialLabel.setPadding(0, 10, 0, 5)
    about_layout.addView(socialLabel)
    
    local socialLayout = LinearLayout(activity)
    socialLayout.setOrientation(LinearLayout.VERTICAL)
    socialLayout.setPadding(0, 0, 0, 10)
    
    local socialLinks = {
        {"Telegram Group", "https://t.me/blindtechhubp2s"},
        {"Blind Tech Hub", "https://t.me/blindtechhubq7c"},
        {"SP Tech Hub", "https://t.me/S_P_Tech_Hub"},
        {"Audio Tutorials", "https://t.me/+1Aazfn0FJ9oxZWE1"},
        {"Music Channel", "https://t.me/Noncopyrightbackgrounmusic"},
        {"WhatsApp Community", "https://chat.whatsapp.com/Kb3QOapabwZGOgzzO8FZof"},
        {"WhatsApp Channel", "https://whatsapp.com/channel/0029VbAVDj23AzNYccK2KR3T"},
        {"YouTube Channel", "https://youtube.com/@blindtechhub-p2s"},
        {"Official Website", "https://blind-tech-hub.vercel.app/"},
        {"File Store", "https://drive.google.com/drive/folders/1gELqt9suCksO8SWvEZshmgbs_hrZLZHY"}
    }
    
    for i, link in ipairs(socialLinks) do
        local btn = Button(activity)
        btn.setText(link[1])
        btn.setTextSize(12)
        btn.setBackgroundColor(0xFFEEEEEE)
        btn.setTextColor(0xFF2196F3)
        btn.setPadding(10, 8, 10, 8)
        btn.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        local params = btn.getLayoutParams()
        params.setMargins(0, 3, 0, 3)
        btn.setLayoutParams(params)
        btn.onClick = function()
            local intent = Intent(Intent.ACTION_VIEW, Uri.parse(link[2]))
            activity.startActivity(intent)
        end
        socialLayout.addView(btn)
    end
    
    about_layout.addView(socialLayout)
    
    -- No Close Button - User will use back button
    
    dlg.setView(about_layout)
    dlg.setCancelable(true) -- Allows back button to close
    dlg.show()
end

-- 7. API SETTINGS DIALOG
function openAPISettings()
    local dlg = AlertDialog.Builder(activity)
    local set_layout = LinearLayout(activity)
    set_layout.setOrientation(LinearLayout.VERTICAL)
    set_layout.setPadding(40, 40, 40, 40)
    set_layout.setBackgroundColor(0xFFFFFFFF)

    local providerLabel = TextView(activity)
    providerLabel.setText("Select AI Provider:")
    providerLabel.setTextSize(16)
    providerLabel.setTextColor(0xFF000000)
    providerLabel.setPadding(0, 0, 0, 10)
    set_layout.addView(providerLabel)

    local providerSpinner = Spinner(activity)
    local providers = {"Groq", "OpenRouter"}
    local provAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, providers)
    providerSpinner.setAdapter(provAdapter)
    local currentProv = getCurrentProvider()
    for i = 1, #providers do
        if providers[i] == currentProv then
            providerSpinner.setSelection(i - 1)
            break
        end
    end
    set_layout.addView(providerSpinner)

    local dynamicContainer = LinearLayout(activity)
    dynamicContainer.setOrientation(LinearLayout.VERTICAL)
    dynamicContainer.setPadding(0, 15, 0, 0)
    set_layout.addView(dynamicContainer)

    local groqModels = {"llama-3.1-8b-instant", "llama-3.3-70b-versatile", "mixtral-8x7b-32768", "gemma2-9b-it"}
    local orModels = {"google/gemini-2.0-flash-001", "google/gemini-2.5-pro-exp-03-25", "anthropic/claude-3.7-sonnet"}

    function createGroqFields()
        dynamicContainer.removeAllViews()
        
        local groqLabel = TextView(activity)
        groqLabel.setText("Groq API Key:")
        groqLabel.setTextSize(14)
        groqLabel.setTextColor(0xFF000000)
        groqLabel.setPadding(0, 5, 0, 5)
        dynamicContainer.addView(groqLabel)
        
        local groqInput = EditText(activity)
        groqInput.setId(1001)
        groqInput.setHint("Enter Groq API Key")
        groqInput.setInputType(129)
        local savedGroqKey = getGroqApiKey()
        if savedGroqKey and savedGroqKey ~= "" then
            groqInput.setText(savedGroqKey)
        end
        groqInput.setBackgroundColor(0xFFF5F5F5)
        groqInput.setPadding(15, 10, 15, 10)
        dynamicContainer.addView(groqInput)
        
        local getGroqBtn = Button(activity)
        getGroqBtn.setText("Get Groq API Key")
        getGroqBtn.setTextSize(13)
        getGroqBtn.setBackgroundColor(0xFF4CAF50)
        getGroqBtn.setTextColor(0xFFFFFFFF)
        getGroqBtn.setPadding(10, 12, 10, 12)
        getGroqBtn.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        local params = getGroqBtn.getLayoutParams()
        params.setMargins(0, 10, 0, 10)
        getGroqBtn.setLayoutParams(params)
        getGroqBtn.onClick = function()
            local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://console.groq.com/keys"))
            activity.startActivity(intent)
        end
        dynamicContainer.addView(getGroqBtn)

        local groqModelLabel = TextView(activity)
        groqModelLabel.setText("Groq Model:")
        groqModelLabel.setTextSize(14)
        groqModelLabel.setTextColor(0xFF000000)
        groqModelLabel.setPadding(0, 10, 0, 5)
        dynamicContainer.addView(groqModelLabel)
        
        local groqModelSpinner = Spinner(activity)
        groqModelSpinner.setId(1002)
        local groqModelAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, groqModels)
        groqModelSpinner.setAdapter(groqModelAdapter)
        local currentGroqModel = getGroqModel()
        for i = 1, #groqModels do
            if groqModels[i] == currentGroqModel then
                groqModelSpinner.setSelection(i - 1)
                break
            end
        end
        dynamicContainer.addView(groqModelSpinner)
    end

    function createOpenRouterFields()
        dynamicContainer.removeAllViews()
        
        local orLabel = TextView(activity)
        orLabel.setText("OpenRouter API Key:")
        orLabel.setTextSize(14)
        orLabel.setTextColor(0xFF000000)
        orLabel.setPadding(0, 5, 0, 5)
        dynamicContainer.addView(orLabel)
        
        local orInput = EditText(activity)
        orInput.setId(2001)
        orInput.setHint("Enter OpenRouter API Key")
        orInput.setInputType(129)
        local savedORKey = getOpenRouterKey()
        if savedORKey and savedORKey ~= "" then
            orInput.setText(savedORKey)
        end
        orInput.setBackgroundColor(0xFFF5F5F5)
        orInput.setPadding(15, 10, 15, 10)
        dynamicContainer.addView(orInput)
        
        local getORBtn = Button(activity)
        getORBtn.setText("Get OpenRouter API Key")
        getORBtn.setTextSize(13)
        getORBtn.setBackgroundColor(0xFF4CAF50)
        getORBtn.setTextColor(0xFFFFFFFF)
        getORBtn.setPadding(10, 12, 10, 12)
        getORBtn.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
        local params = getORBtn.getLayoutParams()
        params.setMargins(0, 10, 0, 10)
        getORBtn.setLayoutParams(params)
        getORBtn.onClick = function()
            local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://openrouter.ai/keys"))
            activity.startActivity(intent)
        end
        dynamicContainer.addView(getORBtn)

        local orModelLabel = TextView(activity)
        orModelLabel.setText("OpenRouter Model:")
        orModelLabel.setTextSize(14)
        orModelLabel.setTextColor(0xFF000000)
        orModelLabel.setPadding(0, 10, 0, 5)
        dynamicContainer.addView(orModelLabel)
        
        local orModelSpinner = Spinner(activity)
        orModelSpinner.setId(2002)
        local orModelAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, orModels)
        orModelSpinner.setAdapter(orModelAdapter)
        local currentORModel = getOpenRouterModel()
        for i = 1, #orModels do
            if orModels[i] == currentORModel then
                orModelSpinner.setSelection(i - 1)
                break
            end
        end
        dynamicContainer.addView(orModelSpinner)
    end

    if currentProv == "Groq" then
        createGroqFields()
    else
        createOpenRouterFields()
    end

    providerSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener {
        onItemSelected = function(parent, view, position, id)
            local selected = providers[position + 1]
            if selected == "Groq" then
                createGroqFields()
            else
                createOpenRouterFields()
            end
        end,
        onNothingSelected = function() end
    })

    dlg.setTitle("API Settings")
    dlg.setView(set_layout)
    dlg.setPositiveButton("SAVE", function()
        local selectedProvider = providers[providerSpinner.getSelectedItemPosition() + 1]
        local groqInput = activity.findViewById(1001)
        local groqSpinner = activity.findViewById(1002)
        local orInput = activity.findViewById(2001)
        local orSpinner = activity.findViewById(2002)
        
        saveCurrentProvider(selectedProvider)
        config.currentProvider = selectedProvider
        
        if groqInput then
            local key = groqInput.getText().toString()
            if key and key ~= "" then
                saveGroqApiKey(key)
            end
        end
        if groqSpinner then
            local model = groqModels[groqSpinner.getSelectedItemPosition() + 1]
            if model then
                saveGroqModel(model)
            end
        end
        
        if orInput then
            local key = orInput.getText().toString()
            if key and key ~= "" then
                saveOpenRouterKey(key)
            end
        end
        if orSpinner then
            local model = orModels[orSpinner.getSelectedItemPosition() + 1]
            if model then
                saveOpenRouterModel(model)
            end
        end
        
        showToast("API Settings Saved")
    end)
    dlg.setNegativeButton("CANCEL", nil)
    dlg.show()
end

-- 8. AI FETCH - FIXED FOR FULL RESPONSES
function fetchAI(query)
    local idx = chat_data.size()
    chat_data.add("AI. Thinking...")
    adapter.notifyDataSetChanged()
    
    local safe_query = query:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n")
    local url, key, model_id
    
    if config.currentProvider == "Groq" then
        url = "https://api.groq.com/openai/v1/chat/completions"
        key = getGroqApiKey()
        model_id = getGroqModel()
        
        if not key or key == "" then
            chat_data.set(idx, "Error: Please set Groq API key in Settings")
            adapter.notifyDataSetChanged()
            showToast("Groq API key missing")
            return
        end
    else
        url = "https://openrouter.ai/api/v1/chat/completions"
        key = getOpenRouterKey()
        model_id = getOpenRouterModel()
        
        if not key or key == "" then
            chat_data.set(idx, "Error: Please set OpenRouter API key in Settings")
            adapter.notifyDataSetChanged()
            showToast("OpenRouter API key missing")
            return
        end
    end

    -- Increased max_tokens for full responses
    local post_body = '{"model": "'..model_id..'", "messages": [{"role": "user", "content": "'..safe_query..'"}], "max_tokens": 4096, "temperature": 0.7}'

    playSound(SEND_SOUND)

    Http.post(url, post_body, {
        ["Authorization"] = "Bearer "..key,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "Mozilla/5.0"
    }, function(code, res)
        if code == 200 then
            -- Parse JSON response properly
            local ok, decoded = pcall(cjson.decode, res)
            if ok and decoded and decoded.choices and decoded.choices[1] then
                local text = decoded.choices[1].message.content
                if text and text ~= "" then
                    local time = getCurrentTime()
                    chat_data.set(idx, "AI. "..text.." Received at: "..time)
                    playSound(RECEIVE_SOUND)
                else
                    chat_data.set(idx, "AI. No response received")
                    showToast("No response received")
                end
            else
                -- Fallback to regex if JSON parsing fails
                local text = res:match('"content":%s*"(.-)"')
                if text then
                    text = text:gsub("\\n", "\n"):gsub("\\\"", "\""):gsub("\\\\", "\\")
                    local time = getCurrentTime()
                    chat_data.set(idx, "AI. "..text.." Received at: "..time)
                    playSound(RECEIVE_SOUND)
                else
                    chat_data.set(idx, "AI. Parsing Error")
                    showToast("Parsing Error")
                    print("Raw response: " .. res)
                end
            end
        else
            local errMsg = "Error "..tostring(code)
            if code == 401 then
                errMsg = "Invalid API key"
                showToast("Invalid API Key")
            elseif code == 429 then
                errMsg = "Rate limit exceeded"
                showToast("Rate limit exceeded")
            else
                errMsg = "Error: "..code
                showToast("Error: "..code)
            end
            chat_data.set(idx, "AI. "..errMsg)
            print("Response error: " .. res)
        end
        adapter.notifyDataSetChanged()
        chat_window.setSelection(chat_data.size() - 1)
    end)
end

-- 9. MESSAGE HOLD HANDLER
function showMessageOptions(position)
    local message = chat_data.get(position)
    if not message then return end
    
    local displayMsg = message:gsub("^[^.]%.%s*", "")
    displayMsg = displayMsg:gsub("%s+Received at:.*$", "")
    displayMsg = displayMsg:gsub("%s+Send at:.*$", "")
    
    local options = {
        "Copy",
        "Share", 
        "Delete"
    }
    
    local dlg = AlertDialog.Builder(activity)
    dlg.setTitle("Message Options")
    dlg.setItems(options, function(dialog, which)
        if which == 0 then
            activity.getSystemService(Context.CLIPBOARD_SERVICE).setText(displayMsg)
            showToast("Copied")
        elseif which == 1 then
            local shareIntent = Intent(Intent.ACTION_SEND)
            shareIntent.setType("text/plain")
            shareIntent.putExtra(Intent.EXTRA_TEXT, displayMsg)
            activity.startActivity(Intent.createChooser(shareIntent, "Share via"))
        elseif which == 2 then
            chat_data.remove(position)
            adapter.notifyDataSetChanged()
            showToast("Deleted")
        end
    end)
    dlg.show()
end

-- 10. SEND MESSAGE WITH DELAY
function sendMessageWithDelay(text)
    local time = getCurrentTime()
    chat_data.add("Me. "..text.." Send at: "..time)
    adapter.notifyDataSetChanged()
    chat_window.setSelection(chat_data.size() - 1)
    
    handler.postDelayed(Runnable {
        run = function()
            fetchAI(text)
        end
    }, 500)
end

-- 11. VOICE RECOGNITION
function startVoiceRecognition()
    if isVoiceRecording then return end
    isVoiceRecording = true
    
    voice_btn.setText("Recording...")
    voice_btn.setBackgroundColor(0xFFFF0000)
    voice_btn.setTextColor(0xFFFFFFFF)
    
    local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
    intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak now...")
    activity.startActivityForResult(intent, 101)
end

-- 12. LISTENERS
more_btn.onClick = function() showMoreOptions() end

send_btn.onClick = function()
    local t = tostring(user_input.getText())
    if t ~= "" then 
        sendMessageWithDelay(t)
        user_input.setText("") 
    end
end

voice_btn.setOnTouchListener(View.OnTouchListener {
    onTouch = function(view, event)
        local action = event.getAction()
        if action == MotionEvent.ACTION_DOWN then
            startVoiceRecognition()
            return true
        elseif action == MotionEvent.ACTION_UP or action == MotionEvent.ACTION_CANCEL then
            isVoiceRecording = false
            voice_btn.setText("Voice Message")
            voice_btn.setBackgroundColor(0x00000000)
            voice_btn.setTextColor(0xff2196F3)
            return true
        end
        return false
    end
})

function onActivityResult(requestCode, resultCode, data)
    if requestCode == 101 then
        isVoiceRecording = false
        voice_btn.setText("Voice Message")
        voice_btn.setBackgroundColor(0x00000000)
        voice_btn.setTextColor(0xff2196F3)
        
        if resultCode == activity.RESULT_OK then
            local res = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            if res and res.size() > 0 then
                local spoken = tostring(res.get(0))
                if spoken and spoken ~= "" then
                    sendMessageWithDelay(spoken)
                end
            end
        end
    end
end

chat_window.setOnItemLongClickListener(AdapterView.OnItemLongClickListener {
    onItemLongClick = function(parent, view, position, id)
        showMessageOptions(position)
        return true
    end
})

if getGroqApiKey() == "" and getOpenRouterKey() == "" then
    activity.runOnUiThread(function()
        local dlg = AlertDialog.Builder(activity)
        dlg.setTitle("Welcome")
        dlg.setMessage("Please set your API keys in Settings to start chatting.")
        dlg.setPositiveButton("Open API Settings", function()
            openAPISettings()
        end)
        dlg.setNegativeButton("Later", nil)
        dlg.show()
    end)
end