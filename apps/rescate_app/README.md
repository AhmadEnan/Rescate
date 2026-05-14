# Rescate App UI

This is the main Flutter application entry point.

Based on the project's **Feature-Based Architecture**, UI components should be strictly placed within `lib/features/`.
This folder should NOT contain logic for AI inference, offline databases, or mesh networking. Those reside in the `packages/` directory.

### Running the App
To run the app, ensure you have fetched workspace dependencies from the root, then run:

```bash
flutter run
```
