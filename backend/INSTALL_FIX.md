# Fix Backend Install (Rust / cv2 errors)

## Option A: Use pre-built wheels (recommended)

1. **Upgrade pip** (often fixes missing wheel):
   ```bash
   python -m pip install --upgrade pip
   ```

2. **Install from requirements without building from source**:
   ```bash
   pip install --only-binary :all: -r requirements.txt
   ```
   If that fails (some package has no wheel), continue to step 3.

3. **Install step by step** (so OpenCV installs even if pydantic had issues):
   ```bash
   pip install "pydantic>=2.8.0,<2.10.0"
   pip install fastapi uvicorn python-multipart numpy
   pip install opencv-python-headless
   ```

4. **Run the backend**:
   ```bash
   python main.py
   ```
   If `cv2` is still missing, the API will run with fallback (no bald/graft detection). To get OpenCV:
   ```bash
   pip install opencv-python
   ```
   (uses regular opencv-python if headless fails.)

## Option B: Install Rust (only if you need pydantic 2.10+)

1. Install Rust: https://rustup.rs/
2. Restart terminal, then:
   ```bash
   pip install -r requirements.txt
   ```
