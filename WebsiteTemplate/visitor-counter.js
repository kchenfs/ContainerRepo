async function updateVisitorCount() {
    const API_ENDPOINT = 'https://w906yq6h7k.execute-api.ca-central-1.amazonaws.com/prod/myresource';
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
            body: JSON.stringify({})
        });
        
        if (response.ok) {
            // Parse the response as JSON
            const data = await response.json();
            console.log('Raw response:', response);
            console.log('Response status:', response.status);
            console.log('Raw data received:', data);
            console.log('typeof data:', typeof data);
            
            // Extract the count from the JSON response
            const count = parseInt(data.count);
            console.log ('Parsed count:', count);
            if (!isNaN(count)) {
                // Format the number with commas for better readability
                countElement.textContent = (count);
                console.log('Visitor count updated successfully:', count);
            } else {
                throw new Error('Invalid count received from API');
            }
            
        } else {
            console.error('Response not OK:', response.status, response.statusText);
            const errorText = await response.text();
            console.error('Error response body:', errorText);
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
    } catch (error) {
        console.error('Error updating visitor count:', error);
        console.error('Error details:', error.message);
        
        // Fallback display
        countElement.textContent = 'Error loading count';
    }
}