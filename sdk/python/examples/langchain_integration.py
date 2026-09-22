"""Example: Using Buildify with LangChain (as a standard OpenAI-compatible ChatModel)."""

# Since Buildify strictly adheres to the OpenAI API spec,
# you can use it with LangChain's ChatOpenAI directly!

from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage

def main():
    phone_ip = "192.168.1.55" # Replace with your phone IP or use Buildify discovery
    
    # Initialize LangChain ChatOpenAI pointing to Buildify phone
    llm = ChatOpenAI(
        base_url=f"http://{phone_ip}:8080/v1",
        api_key="not-needed", # Buildify runs locally without mandatory keys
        model="gemma-2b",
        temperature=0.7,
        streaming=True,
    )

    messages = [
        SystemMessage(content="You are a helpful assistant running on an Android edge server."),
        HumanMessage(content="What makes edge computing exciting?"),
    ]

    print("Streaming LangChain response from phone:\n")
    for chunk in llm.stream(messages):
        print(chunk.content, end="", flush=True)
    print("\n")

if __name__ == "__main__":
    main()
