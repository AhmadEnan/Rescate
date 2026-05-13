class RingBuffer<T> {
  RingBuffer(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<T> _items = <T>[];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isFull => _items.length == capacity;

  void push(T value) {
    if (_items.length == capacity) {
      _items.removeAt(0);
    }
    _items.add(value);
  }

  T? pop() {
    if (_items.isEmpty) {
      return null;
    }
    return _items.removeAt(0);
  }

  List<T> toList() {
    return List<T>.unmodifiable(_items);
  }
}
