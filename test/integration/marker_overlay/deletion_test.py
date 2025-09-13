# Test file for deletion markers

def unused_function():
    """This function is no longer needed"""
    print("Deprecated code")
    return None

def calculate(x, y):
    # Verbose implementation
    result = 0
    result = result + x
    result = result + y
    print(f"Debug: {result}")
    return result

class OldClass:
    def __init__(self):
        self.value = 0

    def deprecated_method(self):
        pass

def main():
    x = 5
    y = 10
    sum = calculate(x, y)
    print(f"Result: {sum}")

if __name__ == "__main__":
    main()

-- CLAUDE:MARKERS:START --
CLAUDE:MARKER-1,1 | Add module docstring
"""Module for testing marker operations including deletions"""
CLAUDE:MARKER-3,-4 | Remove unused function that's no longer needed
CLAUDE:MARKER-8,7 | Simplify verbose calculate function (including extra return)
def calculate(x, y):
    """Simple addition of two numbers"""
    return x + y
CLAUDE:MARKER-15,-7 | Remove deprecated OldClass entirely (including trailing pass)
CLAUDE:MARKER-22,0 | Add type hints import

from typing import Optional
CLAUDE:MARKER-23,1 | Improve main function signature
def main() -> None:
CLAUDE:MARKER-24,0 | Add docstring after function definition
    """Main entry point of the application"""
CLAUDE:MARKER-28,0 | Add error handling

    try:
        print(f"Result: {sum}")
    except Exception as e:
        print(f"Error: {e}")
-- CLAUDE:MARKERS:END --