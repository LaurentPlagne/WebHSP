from playwright.sync_api import sync_playwright, expect

def run(playwright):
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto("http://localhost:8501", timeout=60000)

    page.wait_for_load_state('networkidle')

    # There are multiple iframes on the page, we need to find the correct one.
    # The component is likely the last one added.
    iframe_locator = page.locator("iframe").last

    # Wait for the graph to be rendered inside the iframe
    graph_container = iframe_locator.frame_locator(":scope").locator("#network-graph svg")

    try:
        expect(graph_container).to_be_visible(timeout=20000)
        print("SUCCESS: Graph SVG is visible inside the iframe.")
    except Exception as e:
        print("ERROR: Graph SVG not found inside the iframe.")
        print(e)


    page.screenshot(path="jules-scratch/verification/verification.png")
    browser.close()
    print("Screenshot taken and browser closed.")

with sync_playwright() as playwright:
    run(playwright)
