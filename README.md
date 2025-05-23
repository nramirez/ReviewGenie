# ReviewGenie

## Demo

[Link to Demo Video](https://youtu.be/EOib8zWpLXY)

## Features

- **Photo Location with New Places APIs:** Accurately identify and tag photo locations using Google's latest Places API.
- **Contextual Review Generation with Gemini:** Generate insightful and relevant reviews by leveraging the context from previous reviews, powered by Gemini.
- **AI-Assisted Image Descriptions with Gemini Vision:** Automatically generate descriptive text for images, making it easier to understand their content, thanks to Gemini Vision.
- **Photo History Index:** Keep track of all visited places with an organized photo history, simplifying the process of writing reviews for past experiences.
- **Easy Google Maps Integration:** Seamlessly post your reviews and photos directly to Google Maps.
- **Clear All Data:** Easily clear all stored data, including reviews and photos, with a dedicated action button.

## Getting Started

### Prerequisites

Before you begin, ensure you have the following:

1. **Google Maps API Keys:** You'll need to add your own Google Maps API keys. You can find information on how to get these and enable the necessary services at [Places API (New)](https://developers.google.com/maps/documentation/places/web-service/overview).

2. **Firebase and Vertex AI Setup:** For features like grounding with Search using Gemini Vision and Gemini API for reviews, you will need to set up Firebase and Vertex AI. Download your `GoogleService-Info.plist` file from your Firebase project console.

3. **Claude API Key (Optional):** If you wish to use an additional LLM, you can add an API key for Claude.

### Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/ReviewGenie.git
   cd ReviewGenie
   ```

2. **Configure API Keys and Firebase:**
   - Place your `GoogleService-Info.plist` file in the `ReviewGenie` directory
   - Add your Google Maps Places API key to `GoogleService-Info.plist` by adding the following key-value pair:
     ```xml
     <key>GOOGLE_MAPS_PLACES_API_KEY</key>
     <string>YOUR_PLACES_API_KEY</string>
     ```
   - Create `APIKeys-Info.plist` in the `ReviewGenie` directory and add your Claude API key:
     ```xml
     <key>CLAUDE_API_KEY</key>
     <string>YOUR_CLAUDE_API_KEY</string>
     <key>CLAUDE_API_VERSION</key>
     <string>2023-06-01</string>
     ```

3. **Open the project in Xcode:**
   - Open `ReviewGenie.xcodeproj` in Xcode
   - Select the project in the navigator
   - Select the ReviewGenie target
   - Build and Run the project

4. **Build and Run:**
   Select your target device or simulator and click the Run button in Xcode.

### Security Note

The following files contain sensitive information and should never be committed to version control:
- `GoogleService-Info.plist` (contains Firebase configuration and API keys)
- `APIKeys-Info.plist` (contains additional API keys)

These files are already included in `.gitignore`. If you're forking this project, make sure to create your own configuration files and add your own API keys.