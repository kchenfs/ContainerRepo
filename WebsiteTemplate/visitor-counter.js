// visitor-counter.js
// Handles visitor count API calls and updates the display

// Configuration - Replace with your actual API Gateway endpoint
const API_ENDPOINT = 'https://w906yq6h7k.execute-api.ca-central-1.amazonaws.com/prod/myresource';

/**
 * Fetches and updates the visitor count from the API
 * Updates the element with id="visitor-count"
 */
async function updateVisitorCount() {
    const countElement = document.getElementById('visitor-count');
    
    if (!countElement) {
        console.error('Visitor count element not found');
        return;
    }

    try {
        // Show loading state
        countElement.textContent = 'Loading...';
        
        // Make API call to your Lambda function
        const response = await fetch(API_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            // Your Lambda doesn't seem to use the request body, but keeping it for consistency
            body: JSON.stringify({})
        });
        
        if (response.ok) {
            // Parse the response as JSON
            const data = await response.json();
            
            // Extract the count from the JSON response
            // Your Lambda returns { visit_count: "123" }
            const count = parseInt(data.visit_count);
            
            if (!isNaN(count)) {
                // Format the number with commas for better readability
                countElement.textContent = formatNumber(count);
                console.log('Visitor count updated successfully:', count);
            } else {
                throw new Error('Invalid count received from API');
            }
            
        } else {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
    } catch (error) {
        console.error('Error updating visitor count:', error);
        
        // Fallback display
        countElement.textContent = 'Error loading count';
        
        // Optional: Show a fallback number instead of error
        // countElement.textContent = '---';
    }
}

/**
 * Formats a number with commas for thousands
 * @param {number} num - The number to format
 * @returns {string} - Formatted number string
 */
function formatNumber(num) {
    if (typeof num !== 'number') {
        return String(num);
    }
    return num.toLocaleString();
}

/**
 * Optional: Retry mechanism for failed requests
 * @param {number} maxRetries - Maximum number of retry attempts
 * @param {number} delay - Delay between retries in milliseconds
 */
async function updateVisitorCountWithRetry(maxRetries = 3, delay = 1000) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            await updateVisitorCount();
            return; // Success, exit the retry loop
        } catch (error) {
            console.warn(`Attempt ${attempt} failed:`, error);
            
            if (attempt === maxRetries) {
                console.error('All retry attempts failed');
                const countElement = document.getElementById('visitor-count');
                if (countElement) {
                    countElement.textContent = 'Unavailable';
                }
            } else {
                // Wait before retrying
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }
}