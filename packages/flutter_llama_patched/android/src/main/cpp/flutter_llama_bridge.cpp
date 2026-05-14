/*
 * Flutter Llama - JNI Bridge for Android
 * 
 * This file provides JNI bindings between Kotlin and llama.cpp
 * Updated for latest llama.cpp API
 */

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <android/log.h>

#define LOG_TAG "FlutterLlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Include llama.cpp headers
#include "llama.h"

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_context = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::mutex g_mutex;
static bool g_should_stop = false;
static std::vector<std::string> g_stream_tokens;
static size_t g_stream_pos = 0;

// Log callback for llama.cpp
static void llama_log_callback(ggml_log_level level, const char * text, void * user_data) {
    if (level == GGML_LOG_LEVEL_ERROR) {
        LOGE("llama.cpp: %s", text);
    } else if (level == GGML_LOG_LEVEL_WARN) {
        LOGI("llama.cpp (WARN): %s", text);
    } else {
        // Strip newlines from normal info logs to prevent logcat spam formatting issues
        std::string str(text);
        if (!str.empty() && str.back() == '\n') str.pop_back();
        LOGI("llama.cpp: %s", str.c_str());
    }
}

extern "C" {

// Initialize and load model
JNIEXPORT jboolean JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeInitModel(
    JNIEnv* env,
    jobject thiz,
    jstring model_path,
    jint n_threads,
    jint n_gpu_layers,
    jint context_size,
    jint batch_size,
    jboolean use_gpu,
    jboolean verbose
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    const char* path = env->GetStringUTFChars(model_path, nullptr);
    
    LOGI("Initializing model: %s", path);
    LOGI("Threads: %d, GPU layers: %d, Context: %d", n_threads, n_gpu_layers, context_size);
    
    // Free existing model if any
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }
    
    // Setup logging
    llama_log_set(llama_log_callback, nullptr);

    // Load dynamic backends
    ggml_backend_load_all();
    
    // Set up model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = use_gpu ? n_gpu_layers : 0;
    
    // Load model
    g_model = llama_model_load_from_file(path, model_params);
    if (!g_model) {
        LOGE("Failed to load model from: %s", path);
        env->ReleaseStringUTFChars(model_path, path);
        return JNI_FALSE;
    }
    
    // Get vocab
    g_vocab = llama_model_get_vocab(g_model);
    
    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size;
    ctx_params.n_batch = batch_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGE("Failed to create context");
        llama_free_model(g_model);
        g_model = nullptr;
        env->ReleaseStringUTFChars(model_path, path);
        return JNI_FALSE;
    }
    
    // Initialize sampler chain
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add samplers
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    LOGI("Model loaded successfully");
    LOGI("Context size: %d", llama_n_ctx(g_context));
    
    env->ReleaseStringUTFChars(model_path, path);
    return JNI_TRUE;
}

// Generate text
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerate(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context || !g_vocab) {
        LOGE("Model not loaded");
        return nullptr;
    }
    
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    LOGI("Generating with prompt: %.50s...", prompt_str);
    
    std::string prompt_text(prompt_str);
    env->ReleaseStringUTFChars(prompt, prompt_str);
    
    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);
    
    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        LOGE("Failed to tokenize prompt");
        return nullptr;
    }
    
    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());
    
    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        LOGE("Failed to decode prompt");
        return nullptr;
    }
    
    // Update sampler with new parameters
    llama_sampler_free(g_sampler);
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Generate tokens
    std::string result;
    int n_generated = 0;
    int n_pos = prompt_tokens.size();
    
    g_should_stop = false;
    
    for (int i = 0; i < max_tokens; i++) {
        if (g_should_stop) {
            LOGI("Generation stopped by user");
            break;
        }
        
        // Sample next token
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
        
        // Check for EOS
        if (llama_vocab_is_eog(g_vocab, new_token)) {
            LOGI("EOS token reached");
            break;
        }
        
        // Convert token to text
        char token_str[256] = {0};
        int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
        if (n > 0) {
            token_str[n] = '\0';
            result.append(token_str);
        }
        
        // Prepare for next iteration
        batch = llama_batch_get_one(&new_token, 1);
        n_pos++;
        
        if (llama_decode(g_context, batch) != 0) {
            LOGE("Failed to decode token");
            break;
        }
        
        n_generated++;
    }
    
    LOGI("Generated %d tokens", n_generated);
    
    // Create GenerationResult object
    jclass result_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$GenerationResult");
    if (!result_class) {
        LOGE("Failed to find GenerationResult class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(result_class, "<init>", "(Ljava/lang/String;I)V");
    if (!constructor) {
        LOGE("Failed to find GenerationResult constructor");
        return nullptr;
    }
    
    jstring j_result = env->NewStringUTF(result.c_str());
    jobject generation_result = env->NewObject(result_class, constructor, j_result, n_generated);
    
    return generation_result;
}

// Initialize streaming generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamInit(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Initializing stream generation");
    
    if (!g_model || !g_context || !g_vocab) {
        LOGE("Model not loaded");
        return;
    }
    
    g_should_stop = false;
    g_stream_tokens.clear();
    g_stream_pos = 0;
    
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_text(prompt_str);
    env->ReleaseStringUTFChars(prompt, prompt_str);
    
    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);
    
    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        LOGE("Failed to tokenize prompt");
        return;
    }
    
    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());
    
    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        LOGE("Failed to decode prompt");
        return;
    }
    
    // Update sampler
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Pre-generate tokens loop removed for true streaming
    LOGI("Stream initialized, waiting for next token calls");
}

// Get next token in stream
JNIEXPORT jstring JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamNext(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (g_should_stop) {
        return nullptr;
    }
    
    llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
    
    if (llama_vocab_is_eog(g_vocab, new_token)) {
        return nullptr;
    }
    
    char token_str[256] = {0};
    int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
    
    llama_batch batch = llama_batch_get_one(&new_token, 1);
    
    if (llama_decode(g_context, batch) != 0) {
        return nullptr;
    }
    
    if (n > 0) {
        token_str[n] = '\0';
        return env->NewStringUTF(token_str);
    }
    
    return env->NewStringUTF("");
}

// End streaming generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamEnd(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Ending stream generation");
    g_stream_tokens.clear();
    g_stream_pos = 0;
}

// Get model information
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGetModelInfo(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context) {
        return nullptr;
    }
    
    jlong n_params = llama_model_n_params(g_model);
    jint n_layers = llama_model_n_layer(g_model);
    jint context_size = llama_n_ctx(g_context);
    
    LOGI("Model info: params=%lld, layers=%d, context=%d", 
         (long long)n_params, n_layers, context_size);
    
    // Create ModelInfo object
    jclass info_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$ModelInfo");
    if (!info_class) {
        LOGE("Failed to find ModelInfo class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(info_class, "<init>", "(JII)V");
    if (!constructor) {
        LOGE("Failed to find ModelInfo constructor");
        return nullptr;
    }
    
    jobject model_info = env->NewObject(info_class, constructor, n_params, n_layers, context_size);
    return model_info;
}

// Free model
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeFreeModel(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Freeing model");
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }
    
    g_vocab = nullptr;
    
    LOGI("Model freed successfully");
}

// Stop generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeStopGeneration(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Stopping generation");
    g_should_stop = true;
}

} // extern "C"
