"""Module for testing marker operations including deletions"""


def calculate(x, y):
    """Simple addition of two numbers"""
    return x + y


from typing import Optional
def main() -> None:
    x = 5
    """Main entry point of the application"""
    y = 10
    sum = calculate(x, y)
    print(f"Result: {sum}")


    try:
        print(f"Result: {sum}")
    except Exception as e:
        print(f"Error: {e}")
if __name__ == "__main__":
    main()
