import json

d = json.load(open('/home/melezaly/Projects/Rescate/eval/rag_mirror/sentences.json'))
lens = [len(s['text'].encode('utf-8')) for s in d]
print('sentences:', len(d))
print('total text bytes:', sum(lens))
print('vectors f32 bytes:', len(d) * 1024 * 4)
print('vectors i8 bytes:', len(d) * 1024)
