import os
import re
from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie
from urllib.parse import quote_plus, urlparse, unquote
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get database URL from environment variable
# For MongoDB: mongodb://user:password@host:port/database
# Example: mongodb://localhost:27017/eventdb
# For cloud hosting (MongoDB Atlas, Railway, Render, etc.): Use MONGODB_URL or DATABASE_URL
MONGODB_URL = os.getenv("MONGODB_URL") or os.getenv("DATABASE_URL")

def encode_mongodb_password(url: str) -> str:
    """
    Encode password in MongoDB URL if it contains special characters.
    Handles URLs like: mongodb+srv://user:pass@word@host/db
    Converts to: mongodb+srv://user:pass%40word@host/db
    """
    if not url:
        return url
    
    # Check if URL has multiple @ symbols (indicating unencoded password with @)
    at_count = url.count('@')
    if at_count <= 1:
        # URL looks fine, return as-is (password might already be encoded or has no @)
        return url
    
    # URL has multiple @ symbols, need to fix it
    # Pattern: mongodb+srv://username:password@host/database
    # If password contains @, we have: mongodb+srv://username:pass@word@host/database
    # We need to find the last @ which separates credentials from host
    try:
        # Find the protocol part (mongodb:// or mongodb+srv://)
        protocol_match = re.match(r'(mongodb\+?srv?://)(.+)', url)
        if not protocol_match:
            return url
        
        protocol = protocol_match.group(1)  # mongodb+srv://
        rest = protocol_match.group(2)  # user:pass@word@host/db
        
        # Split by @ to get all parts
        parts = rest.split('@')
        if len(parts) < 2:
            return url
        
        # Last part is host/database
        host_part = parts[-1]
        
        # Everything before last @ should be credentials
        credentials = '@'.join(parts[:-1])  # user:pass@word
        
        # Split credentials into username:password
        if ':' in credentials:
            user_pass = credentials.split(':', 1)
            username = user_pass[0]
            password = user_pass[1] if len(user_pass) > 1 else ''
            
            # Encode the password
            encoded_password = quote_plus(password, safe='')
            
            # Reconstruct URL
            return f"{protocol}{username}:{encoded_password}@{host_part}"
    except Exception:
        # If parsing fails, return original URL
        pass
    
    return url

# Extract database name from URL or use environment variable
DB_NAME = os.getenv("DB_NAME", "eventdb")

if not MONGODB_URL:
    # Fallback: construct from individual components if MONGODB_URL is not set
    db_user = os.getenv("DB_USER", "")
    db_password = os.getenv("DB_PASSWORD", "")
    db_host = os.getenv("DB_HOST", "localhost")
    db_port = os.getenv("DB_PORT", "27017")
    
    # URL-encode password in case it contains special characters
    encoded_password = quote_plus(db_password) if db_password else ""
    
    if db_user and encoded_password:
        MONGODB_URL = f"mongodb://{db_user}:{encoded_password}@{db_host}:{db_port}/{DB_NAME}?authSource=admin"
    else:
        MONGODB_URL = f"mongodb://{db_host}:{db_port}/{DB_NAME}"
else:
    # Encode password if it contains special characters like @
    MONGODB_URL = encode_mongodb_password(MONGODB_URL)
    
    # Extract database name from URL if provided
    try:
        parsed = urlparse(MONGODB_URL)
        if parsed.path and parsed.path != "/":
            DB_NAME = parsed.path.strip("/").split("/")[0] or DB_NAME
    except Exception:
        pass  # Use default DB_NAME if parsing fails

# MongoDB client
client = None

async def init_db():
    """Initialize MongoDB connection and Beanie"""
    global client
    
    # Ensure SSL/TLS is enabled for MongoDB Atlas connections
    connection_url = MONGODB_URL
    if "mongodb+srv://" in connection_url and "tls=true" not in connection_url and "ssl=true" not in connection_url:
        # Add SSL parameters if not present
        separator = "&" if "?" in connection_url else "?"
        connection_url = f"{connection_url}{separator}tls=true"
    
    client = AsyncIOMotorClient(
        connection_url,
        serverSelectionTimeoutMS=30000,  # 30 seconds timeout
        connectTimeoutMS=30000,
    )
    
    # Import models here to avoid circular imports
    from models import ApprovalRequest, ChatConversation, ChatMessage, Event, Invite, ItRequest, MarketingRequest, Publication, User, Venue
    
    # Initialize Beanie with the database and document models
    await init_beanie(
        database=client[DB_NAME],
        document_models=[User, Venue, Event, ApprovalRequest, MarketingRequest, ItRequest, Invite, Publication, ChatConversation, ChatMessage]
    )

async def close_db():
    """Close MongoDB connection"""
    global client
    if client:
        client.close()
