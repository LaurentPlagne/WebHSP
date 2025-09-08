import asyncio
from playwright.async_api import async_playwright, expect

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()

        # Navigate to the main page
        await page.goto("http://127.0.0.1:5000")

        # Wait for the network graph to have some content
        await expect(page.locator('#network-graph canvas')).to_be_visible(timeout=10000)

        # Give it a brief moment to settle the layout
        await page.wait_for_timeout(2000) # Increased wait time for stability

        # Take a screenshot of the valley graph
        await page.screenshot(path="jules-scratch/verification/valley_graph.png")
        print("Screenshot 'valley_graph.png' taken.")

        # Click the "Run Simulation" button
        await page.get_by_role("button", name="Run Simulation").click()

        # Wait for the results page to load
        await page.wait_for_url("**/results.html", timeout=10000)

        # Wait for the results plot to be visible
        await expect(page.locator('#results-plot .plot-container')).to_be_visible(timeout=10000)

        # Give it a brief moment to render
        await page.wait_for_timeout(1000)

        # Take a screenshot of the volume plot
        await page.screenshot(path="jules-scratch/verification/volume_plot.png")
        print("Screenshot 'volume_plot.png' taken.")

        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
