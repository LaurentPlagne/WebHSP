from playwright.sync_api import Page, expect

def test_screenshot(page: Page):
    page.goto("http://localhost:8501")
    expect(page).to_have_title("Hydro Valley Visualizer & Computer")
    page.screenshot(path="jules-scratch/verification/verification.png")
