import firebase_admin
from firebase_admin import credentials, firestore
from newsapi import NewsApiClient
from openai import OpenAI
import hashlib
import os

# ================= CONFIGURATION =================
# Use environment variables for secrets. Set these in your environment or
# in a secrets manager; do NOT commit real keys to the repository.
NEWS_API_KEY = os.getenv("NEWS_API_KEY", "REPLACE_NEWS_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "REPLACE_OPENAI_API_KEY")

# Initialize 1: NewsAPI
newsapi = NewsApiClient(api_key=NEWS_API_KEY)

# Initialize 2: OpenAI
client = OpenAI(api_key=OPENAI_API_KEY)

# Initialize 3: Firebase Database
# We use the JSON file you downloaded to log in automatically
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def summarize_article(title, description):
    """
    Uses OpenAI to turn a news blurb into 3 bullet points.
    """
    prompt = f"""
    You are a news editor for a Gen-Z news app. 
    Summarize the following news article into exactly 3 short, punchy bullet points.
    Do not use introductory text. Just the bullets.
    
    Article Title: {title}
    Context: {description}
    """
    
    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini", # Cheap and fast model
            messages=[{"role": "user", "content": prompt}],
            max_tokens=150
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"Error summarizing: {e}")
        return description # Fallback to original text if AI fails

def run_news_pipeline():
    print("🚀 Fetching top news...")
    
    # 1. Get raw news (e.g., Tech news from US)
    top_headlines = newsapi.get_top_headlines(
        category='technology',
        language='en',
        country='us',
        page_size=10 # Limit to 10 for testing
    )

    articles = top_headlines.get('articles', [])
    print(f"Found {len(articles)} articles. Processing...")

    for article in articles:
        # SKIP if the article has no image (Tinder UI needs images!)
        if not article['urlToImage']:
            print(f"Skipping {article['title']} (No image)")
            continue

        # 2. Create a unique ID for the article (using the URL)
        # This prevents adding the same article twice if you run the script again.
        article_id = hashlib.md5(article['url'].encode()).hexdigest()
        
        # Check if we already have this article in Firebase
        doc_ref = db.collection('news_segments').document(article_id)
        if doc_ref.get().exists:
            print(f"Skipping {article['title']} (Already in DB)")
            continue

        print(f"🧠 AI Summarizing: {article['title']}...")
        
        # 3. Generate AI Summary
        ai_summary = summarize_article(article['title'], article['description'])

        # 4. Prepare data for Firebase
        news_data = {
            "title": article['title'],
            "summary": ai_summary,
            "imageUrl": article['urlToImage'],
            "articleUrl": article['url'],
            "source": article['source']['name'],
            "publishedAt": article['publishedAt'],
            "likes": 0 # We will increment this later in the app
        }

        # 5. Upload to Firebase
        doc_ref.set(news_data)
        print(f"✅ Saved to Firebase!")

if __name__ == "__main__":
    run_news_pipeline()
