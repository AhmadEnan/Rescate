/*
 * Flutter Llama - llama.cpp Bridge Header for macOS
 * 
 * C declarations for Swift to call
 */

#ifndef llama_cpp_bridge_h
#define llama_cpp_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

// Initialize and load model
bool llama_init_model(
    const char* model_path,
    int n_threads,
    int n_gpu_layers,
    int ctx_size,
    int batch_size,
    bool use_gpu,
    bool verbose
);

// Generate text
const char* llama_generate(
    const char* prompt,
    int max_tokens,
    float temperature,
    float top_p,
    int top_k,
    float repeat_penalty
);

// Streaming generation
bool llama_generate_stream_start(
    const char* prompt,
    int max_tokens,
    float temperature,
    float top_p,
    int top_k,
    float repeat_penalty
);

const char* llama_generate_stream_next(void);
void llama_generate_stream_end(void);

// Model info
const char* llama_get_model_info(void);

// Cleanup
void llama_bridge_free_model(void);

// Stop generation
void llama_stop_generation(void);

#ifdef __cplusplus
}
#endif

#endif /* llama_cpp_bridge_h */





