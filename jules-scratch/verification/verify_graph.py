import time
from playwright.sync_api import sync_playwright

def run(playwright):
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page()

    # Navigate to the Streamlit app
    page.goto("http://localhost:8501")

    # Wait for the iframe containing the graph to load
    # Streamlit renders components in iframes.
    # We give it a generous timeout to be safe.
    page.wait_for_selector("iframe", timeout=15000)

    # Get the iframe element
    iframe_element = page.query_selector("iframe")
    iframe = iframe_element.content_frame()

    # Wait for the canvas element within the iframe to be rendered by vis.js
    # This is the best indicator that the graph has been drawn.
    canvas_selector = "canvas"
    iframe.wait_for_selector(canvas_selector, timeout=10000)

    # Give it a brief moment to ensure the rendering is fully complete
    time.sleep(2)

    # Take the screenshot
    page.screenshot(path="jules-scratch/verification/valley_graph.png")

    browser.close()

with sync_playwright() as playwright:
    run(playwright)
