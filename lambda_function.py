import spacy
import boto3
import secrets
import string
import math
import re
from rapidfuzz.process import extractOne
import botocore.exceptions
import datetime
import requests
import os
import stripe
import json



# AWS Clients
dynamodb_client = boto3.client('dynamodb')
lex_client = boto3.client('lexv2-runtime')
pinpoint_client = boto3.client('pinpoint')
ses_client = boto3.client('ses')
#spacy language model
nlp = spacy.load("en_core_web_sm")
#stripe
stripe.api_key = os.environ.get('STRIPE_SECRET_KEY')
# Constants
tax_rate = 0.13 

# Receipt Template
receipt_template = """
--------------------------------------
         Momotaro Sushi
--------------------------------------
Date: {}
Order ID: {}
Customer: {}
Phone: {}
--------------------------------------
Items:
{}
--------------------------------------
Subtotal: {}
Tax: {}
Total: {}
--------------------------------------
Pickup Time: {}
--------------------------------------
Thank you for your order!
--------------------------------------
"""

def validate(slots):
    if not slots['CustomerName']:
        return {
            'isValid': False,
            'violatedSlot': 'CustomerName'
        }

    if not slots['PhoneNumber']:
        return {
            'isValid': False,
            'violatedSlot': 'PhoneNumber',
        }

    if not slots['OrderPickUpTime']:
        return {
            'isValid': False,
            'violatedSlot': 'OrderPickUpTime',
        }

    if not slots['ItemChoice']:
        return {
            'isValid': False,
            'violatedSlot': 'ItemChoice',
        }

    return {'isValid': True}

def extract_items_and_quantities(ordered_items):
    doc = nlp(ordered_items)
    
    combined_list = []

    for chunk in doc.noun_chunks:
        quantity = None
        item = None
        for token in chunk:
            if token.pos_ == "NUM":
                quantity = token.text
            else:
                item = chunk.text.replace(quantity, '').strip() if quantity else chunk.text
        if quantity and item:
            combined_list.append((item, quantity))


    print("doc",doc.noun_chunks)
    print("chunk",chunk)
    print("token", token)        
    print("quantity:", quantity)
    print("item:", item)
    return combined_list

def find_closest_match(item_name, menu_items):
    """
    Find the closest match for the given item name in the list of menu items.

    Args:
        item_name (str): The item name extracted from the customer's input.
        menu_items (list): List of item names from the DynamoDB menu table.

    Returns:
        str: The closest matching item name from the menu_items list.
    """
    match, score, _ = extractOne(item_name, menu_items)
    print('the customer ordered the following items', item_name)
    print('this is the closest match in our database', match)
    print('this is the confidence score', score)
    return match if score >= 80 else None

def parse_ordered_items(combined_list, menu_items):
    print("Before we apply the fuzzy matching", combined_list)
    parsed_items = []
    print(combined_list)
    for entry in combined_list:
        if len(entry) == 2:
            name, quantity = entry
        else:
            name = entry[0]
            quantity = 1

        # Use fuzzy matching to find the closest match in the menu_items list
        closest_match = find_closest_match(name, menu_items)
        print("this is after find_closest_match executes", closest_match)
        parsed_items.append((closest_match, int(quantity)))

    print("Parsed Items:", parsed_items)
    return parsed_items

def format_ordered_items(parsed_items):
    formatted_items = [f"{quantity} {item}" for item, quantity in parsed_items]
    formatted_string = ", ".join(formatted_items)
    return formatted_string

def generate_order_id(length=5):
    characters = string.ascii_letters + string.digits
    order_id = ''.join(secrets.choice(characters) for _ in range(length))
    return order_id.upper()

def get_item_price(item_name):
    # Define the API URL for fetching the price
    api_url = os.environ['ITEM_PRICE_API_URL']
    print(type(item_name))
    print(len(item_name))
    data = {
        'item_name': item_name
    }
    print("get_item_price block",data)
    # Make a GET request to the API
    response = requests.get(api_url, json=data)
    print(response)
    response_data = response.json()
    print("JSONDECODE", response_data)
    price = response_data.get("price")

    if price is not None:
        # Convert the price to a float if needed
        price = float(price)
        return price
    else:
        print(f"Price not found for item: aburi sushi")
        return None

def get_item_names_from_menu_table():
    """
    Retrieve the list of item names from the DynamoDB menu table using a GET request.

    Args:
        api_url (str): The URL of your API Gateway endpoint.

    Returns:
        list: List of item names.
    """
    
    # Define the API Gateway URL
    api_url = os.environ['MENU_ITEMS_API_URL']
    print("MENU_ITEMS_API_URL:", os.environ['MENU_ITEMS_API_URL'])

    # Make a GET request to the API Gateway
    response = requests.get(api_url)
    print(response)
    if response.status_code == 200:
        # Assuming the response contains JSON data with item names
        item_names = response.json()
        print("this is item names", item_names)
        menu_items = item_names.get("items",[])
        print(menu_items)
        return menu_items
    else:
        print('Failed to retrieve item names using the API')
        return None

def save_customer_info(name, ordered_items, phone_number, pickup_time, total_price_with_tax):
    order_id = generate_order_id(5)
    print("save_customer_info", total_price_with_tax)
    order_date = datetime.datetime.now().isoformat()
    # Construct the request body
    data = {
        "order_id": order_id,
        "name": name,
        "ordered_items": ordered_items,
        "phone_number": phone_number,
        "pickup_time": pickup_time,
        "total_price_with_tax": total_price_with_tax,
        "order_date": order_date  # Add the order date
    }


    # Define the API Gateway URL
    api_url = os.environ['SAVE_CUSTOMER_INFO_API_URL']

    # Make a POST request to the API Gateway
    response = requests.post(api_url, json=data)

    if response.status_code == 200:
        print('Successfully saved the info using the API')
        return order_id
    else:
        print('Failed to save the info using the API')
        return None

def generate_receipt(order_date, order_id, customer_name, customer_phone, ordered_items,
                     subtotal_price, tax_amount, total, pickup_time):
    """
    Generate the receipt content based on the provided order details.

    Args:
        order_date (str): Date of the order.
        order_id (str): Order ID.
        customer_name (str): Customer's name.
        customer_phone (str): Customer's phone number.
        ordered_items (str): String representation of ordered items.
        subtotal (str): Subtotal amount.
        tax (str): Tax amount.
        total (str): Total amount.
        pickup_time (str): Pickup time.

    Returns:
        str: Receipt content.
    """
    formatted_order_date = order_date.strftime('%Y-%m-%d %H:%M')

    receipt_content = receipt_template.format(
        formatted_order_date, order_id, customer_name, customer_phone,
        ordered_items, subtotal_price, tax_amount, total, pickup_time
    )
    return receipt_content

def confirm_intent(intent, slots, name, ordered_items, pickup_time, phone_number):
    confirmation_prompt = (
        f"Thanks, {name}! Here's a summary of your order:\n"
        f"You have ordered {ordered_items}.\n"
        f"Your order will be ready for pickup at {pickup_time}.\n"
        f"We will contact you at {phone_number} if needed.\n"
        f"Would you like to confirm your order?"
    )

    return {
        'sessionState': {
            'dialogAction': {
                'type': 'ConfirmIntent',
                'intentName': intent,
                'slots': slots
            },
            'intent': {
                'name': intent,
                'slots': slots
            },
            'sessionAttributes': session_attributes
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': confirmation_prompt
            }
        ]
    }

def send_lex_response(app_id, origination_number, destination_number, messages):
    responses = []
    for message in messages:
        response = pinpoint_client.send_messages(
            ApplicationId=app_id,
            MessageRequest={
                'Addresses': {
                    destination_number: {
                        'ChannelType': 'SMS'
                    }
                },
                'MessageConfiguration': {
                    'SMSMessage': {
                        'Body': message,
                        'MessageType': 'TRANSACTIONAL',
                        'OriginationNumber': origination_number
                    }
                }
            }
        )
        responses.append(response)

    return responses

def handle_sns_message(event):
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    app_id = os.environ['SNS_TOPIC_ID']
    origination_number = sns_message['destinationNumber']
    destination_number = sns_message['originationNumber']
    customer_message = sns_message['messageBody']
    print(customer_message)
    lex_response = lex_client.recognize_text(
        botId = os.environ['LEX_BOT_ID'],
        botAliasId = os.environ['LEX_ALIAS_ID'],
        localeId = 'en_US',
        sessionId = 'user_id',
        text=customer_message
    )

    print("Lex Response:", lex_response)

    messages = [message['content'] for message in lex_response['messages']]

    # Send the complete message as a list
    response = send_lex_response(app_id, origination_number, destination_number, messages)

    return lex_response

def prepare_line_items(session_attributes):
    # Extract relevant information from session_attributes
    item_choices = session_attributes.get("ItemChoice", "").split(", ")
    item_prices = [float(price) for price in session_attributes.get("ItemPrices", "").split(", ")]
    
    print(item_choices, item_prices)
    line_items = []
    for choice, price in zip(item_choices, item_prices):
            quantity = int(choice.split()[0])  # Extract quantity from the item choice
            item_name = " ".join(choice.split()[1:])  # Extract the name of the item

            line_item = {
                'price_data': {
                    'currency': 'cad',
                    'product_data': {
                        'name': item_name,
                    },
                    'unit_amount': int(price * 100),  # Convert price to cents
                },
                'quantity': quantity,
            }

            line_items.append(line_item)

    return line_items


def create_checkout_session(line_items):

    # Create a Checkout Session
    session = stripe.checkout.Session.create(
        payment_method_types=['card'],
        line_items=line_items,
        mode='payment',
        success_url='https://kchenfs.com/',
        billing_address_collection='required'
    )
    
    payment_url = session.url

    return payment_url

# Usage example


def send_email(sender_email, customer_email, subject, body):
    try:
        response = ses_client.send_email(
            Source=sender_email,
            Destination={
                'ToAddresses': [customer_email]
            },
            Message={
                'Subject': {
                    'Data': subject
                },
                'Body': {
                    'Text': {
                        'Data': body
                    }
                }
            }
        )
        print("Email sent successfully:", response)
    except botocore.exceptions.ClientError as e:
        print("Error sending email:", e)


def lambda_handler(event, context):
    print("top of the tree in the lambda handler")
    print(event)
    print(context)
    if 'Records' in event:
        handle_sns_message(event)

        # Handle other SNS message-related operations as needed

    else:
        slots = event['sessionState']['intent']['slots']
        intent = event['sessionState']['intent']['name']
        print("the global access for intent", intent)
        
        if intent == 'Greeting':
            response = {
                'sessionState': {
                    'dialogAction': {
                        'type': 'Close'
                    },
                    'intent': {
                        'name': intent,
                        'slots': slots,
                        'state': 'Fulfilled'
                    }
                },
                'messages': [
                    {
                        'contentType': 'PlainText',
                        'content': "Hello! Welcome to Momotaro Sushi. Here is our menu: [Momotaro Menu](https://momotarosushi.s3.ca-central-1.amazonaws.com/momotaro-sushi-online-menu-.pdf)"
                    },
                    {
                        'contentType': 'PlainText',
                        'content': "If you are ready to order, please type 'pick up' or 'take out'."
                    }
                ]
            }
        
        elif intent == 'RestartIntent':
            response = {
                'sessionState': {
                    'dialogAction': {
                        'type': 'ElicitIntent'
                    },
                    'intent': {
                        'name': 'Greeting',
                        'slots': {},
                        'state': 'Fulfilled'
                    }
                },
                'messages': [
                    {
                        'contentType': 'PlainText',
                        'content': "Hello! Welcome to Momotaro Sushi. Here is our menu: https://momotarosushi.s3.ca-central-1.amazonaws.com/momotaro-sushi-online-menu-.pdf"
                    },
                    {
                        'contentType': 'PlainText',
                        'content': "If you are ready to order, please type 'pick up' or 'take out'."
                    }
                ]
            }
     
        elif intent == 'OrderItem':
           
            validation_result = validate(slots)
            confirmation_state = event['interpretations'][0]['intent']['confirmationState']

            if confirmation_state == 'Confirmed':
                ordered_items = session_attributes['ItemChoice']
                subtotal_price = session_attributes['BillSubtotal']
                tax_amount = session_attributes['BillTaxAmount']
                total_price_with_tax = session_attributes['BillTotal']
                name = session_attributes['CustomerName']
                phone_number = session_attributes['PhoneNumber']
                pickup_time = session_attributes['OrderPickUpTime']
                print("This is in the confirmation=yes block", ordered_items)
            
                # Save customer info to database and get order ID
                print('this is before we save the info to the database', tax_amount, subtotal_price)
                order_id =  save_customer_info(name, ordered_items, phone_number, pickup_time, total_price_with_tax)            
                print('this is after we save the data into the database', tax_amount, subtotal_price)
                session_attributes.update({
                        'OrderId':order_id
                })
                total_price_with_tax = float(total_price_with_tax)  # Convert the string to a float
                
                receipt_message = f"Thanks, {name}, your order has been confirmed. Your total is ${total_price_with_tax:.2f} and the order id is {order_id}, see you at {pickup_time}. Would you like to proceed with the payment now?" \

                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'ElicitSlot',
                            'slotToElicit': 'PaymentConfirmation'
                        },
                        'intent': {
                            'name': 'PayOrder',
                            'state': 'InProgress'
                        },
                        'sessionAttributes': session_attributes  # Save the updated session_attributes with customer info
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': receipt_message
                        }
                    ]
                }
            # ... (other code)

            elif confirmation_state == 'Denied':
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'Close'
                        },
                        'intent': {
                            'name': intent,
                            'state': 'Fulfilled',
                            'slots': {}
                        }
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': "Okay, we won't process your order. If you decide to change your mind, please start over by saying 'cancel'."
                        }
                    ]
                }

            elif event['invocationSource'] == 'DialogCodeHook':#this only executes when we are in the OrderItem intent block and there are missing slot values, So it will return the intent as well as the slots with null values and that will be Lex's response
                validation_result = validate(slots)
                if not validation_result['isValid']:
                    response = {
                        'sessionState': {
                            
                            'dialogAction': {
                                'slotToElicit': validation_result['violatedSlot'],
                                'type': 'ElicitSlot'
                            },
                            'intent': {
                                'name': intent,
                                'slots': slots
                            }
                        }
                    }
                else:
                    # Retrieve session attributes if they exist
                    print("this is in the last elses block of the code before we save the information to attributes")
                    name = slots['CustomerName']['value']['interpretedValue']
                    ordered_items = slots['ItemChoice']['value']['interpretedValue']
                    phone_number = slots['PhoneNumber']['value']['interpretedValue']
                    pickup_time = slots['OrderPickUpTime']['value']['interpretedValue']
                    session_attributes = event['sessionState']['sessionAttributes']
                    # Update the slots dictionary with the values from session_attributes
                    session_attributes.update({
                        'CustomerName': name,
                        'OrderPickUpTime': pickup_time,
                        'PhoneNumber': phone_number
                    })     
                    print("successfully updated the session_attributes", session_attributes)

                    #this line of code needs to be processed first because before the confirmation_intent is executed, by this point all the other slots will have
                    #been filled with a slot value, we then run then apply the fuzzy matching and the spacy libraries to the ordered_items intent and then updated the
                    #slot name ordered_items
                    combined_list = extract_items_and_quantities(ordered_items)
                    print("combined list", combined_list)
                    menu_items = get_item_names_from_menu_table()
                    parsed_items = parse_ordered_items(combined_list, menu_items)
                    print("debugging statement", parsed_items)

                   # Calculate subtotal and directly concatenate item prices with a comma and space
                    subtotal_price = 0
                    item_prices = ""  # Initialize an empty string to store item prices

                    for item, quantity in parsed_items:
                        item_price = get_item_price(item)
                        print(item)
                        print(item_price)
                        item_prices += str(item_price) + ', '  # Concatenate item_price as a string with a comma and space

                        subtotal_price += item_price * quantity

                    # Remove the trailing comma and space if it's not needed
                    if item_prices.endswith(', '):
                        item_prices = item_prices[:-2]


                    print("Here are the prices of each item", item_prices)
                    print("here is the subtotal price", subtotal_price)
                    tax_amount = subtotal_price * tax_rate
                    tax_amount = round(tax_amount, 2)
                    total_price_with_tax = tax_amount + subtotal_price
                    total_price_with_tax = round(total_price_with_tax, 2)
                    ordered_items = format_ordered_items(parsed_items)
                    print(item_prices)
                    print("debugging statement to see how far we get")
                    print(session_attributes)
                    session_attributes.update({
                        'ItemChoice': ordered_items,
                        'BillSubtotal': subtotal_price,
                        'BillTaxAmount': tax_amount,
                        'BillTotal': total_price_with_tax,
                        'ItemPrices': item_prices  # Store the list of item prices

                    })
                    print("sessionAttributes after spacy and fuzzy", session_attributes)    
                    # Call confirm_intent function to generate the confirmation message
                    return {
                        'sessionState': {
                            'dialogAction': {
                                'type': 'ConfirmIntent',
                                'intentName': intent,
                                'slots': slots
                            },
                            'intent': {
                                'name': intent,
                                'slots': slots
                            },
                            'sessionAttributes': session_attributes
                        },
                        'messages': [
                            {
                                'contentType': 'PlainText',
                                'content': f"Thanks, {name}! Here's a summary of your order:\n"
                        f"You have ordered {ordered_items}.\n"
                        f"Your order will be ready for pickup at {pickup_time}.\n"
                        f"We will contact you at {phone_number} if needed.\n"
                        f"Would you like to confirm your order?"
                            }
                        ]
                    }
        
        elif intent == "PayOrder":
            print("This is in the PayOrder intent")
            payment_confirmation = event['sessionState']['intent']['slots']['PaymentConfirmation']['value']['interpretedValue']
            print(event)
            print(payment_confirmation)
            print(session_attributes)

            print("this is the slot value for payment confirmation", payment_confirmation)
            if payment_confirmation == 'Yes':
                # Create a Stripe Checkout session
                print("How far did I make it")
                line_items = prepare_line_items(session_attributes)
                payment_url = create_checkout_session(line_items)
                print('did it work')
                # Provide the URL for the customer to make a payment
                # Define Lex's response to provide the payment URL
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'ElicitIntent'
                        },
                        'intent': {
                            'name': intent,
                            'slots': slots,
                            'state': 'Fulfilled'
                        },
                        'sessionAttributes': session_attributes
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                                'content': f"Great! You can proceed with the payment by following this link: {payment_url}"
                        }
                    ]
                }

            elif payment_confirmation == 'no':
                # Ask if the customer wants a receipt to be sent
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'ElicitSlot',
                            'slotToElicit': 'ReceiptConfirmation'
                        },
                        'intent': {
                            'name': 'EmailReceiptIntent',
                            'state': 'InProgress'
                        },
                        'sessionAttributes': session_attributes
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': "Would you like a copy of your receipt to be sent via email? (yes/no)"
                        }
                    ]
                }

            # Return the appropriate response
    



        elif intent == 'EmailReceiptIntent':
            print(slots)
            receipt_confirmation = slots.get('ReceiptConfirmation', {}).get('value', {}).get('interpretedValue', '').lower()
            email_slot = slots.get('CustomerEmail')

            if not email_slot and receipt_confirmation == 'yes':  # If email_slot is empty, elicit the CustomerEmail slot and the customer says yes to a receipt
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'ElicitSlot',
                            'slotToElicit': 'CustomerEmail'
                        },
                        'intent': {
                            'name': 'EmailReceiptIntent',
                            'slots': slots
                        }
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': 'Please provide the email address you would like to send the receipt to.'
                        }
                    ]
                }
            elif email_slot and receipt_confirmation == 'yes':

                    print("receipt confirmation is 'yes'.")
                    customer_email = email_slot['value']['interpretedValue']
                    sender_email = 'kencfs@outlook.com'  # Replace with your SES sender email
                    subject = 'Momotaro Sushi - Order Receipt'

                    name = session_attributes['CustomerName']
                    ordered_items = session_attributes['ItemChoice']
                    phone_number = session_attributes['PhoneNumber']
                    pickup_time = session_attributes['OrderPickUpTime']
                    order_id = session_attributes['OrderId']
                    subtotal_price = session_attributes['BillSubtotal']
                    tax_amount = session_attributes['BillTaxAmount']
                    total_price_with_tax = session_attributes['BillTotal']
                    print(session_attributes)
                                
                    
                    # Generate the receipt content
                    receipt_content = generate_receipt(
                        order_date=(datetime.datetime.now()),
                        order_id=order_id,
                        customer_name=name,
                        customer_phone=phone_number,
                        ordered_items=ordered_items,
                        subtotal_price=subtotal_price,
                        tax_amount=tax_amount,
                        total=total_price_with_tax,
                        pickup_time=pickup_time
                    )

                    # Send email using Amazon SES
                    send_email(sender_email, customer_email, subject, receipt_content)
                    
                    # Modify Lex's response to include the receipt hyperlink
                    receipt_message = (
                    "The receipt has been sent to your email."
                    )

                    response = {
                        'sessionState': {
                            'dialogAction': {
                                'type': 'Close'
                            },
                            'intent': {
                                'name': intent,
                                'slots': slots,
                                'state': 'Fulfilled'
                            }
                        },
                        'messages': [
                            {
                                'contentType': 'PlainText',
                                'content': receipt_message
                            }
                        ]
                    }

            elif not email_slot and receipt_confirmation == 'no':
                print("Receipt confirmation is 'no'.")
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'Close'
                        },
                        'intent': {
                            'name': intent,
                            'slots': slots,
                            'state': 'Fulfilled'
                        }
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': 'Alright. Your order has been confirmed. Thank you for choosing us!'
                        }
                    ]
                }
            else:
                print("Receipt confirmation is neither 'yes' nor 'no'. Eliciting the FallbackIntent.")
                response = {
                    'sessionState': {
                        'dialogAction': {
                            'type': 'ElicitIntent'
                        },
                        'intent': {
                            'name': 'FallbackIntent',
                            'state': 'Fulfilled'
                        }
                    },
                    'messages': [
                        {
                            'contentType': 'PlainText',
                            'content': "Sorry, I didn't understand your response. Please type 'start over' to restart the ordering process."
                        }
                    ]
                }


    # Return the appropriate response if needed
    print("This is the Lex's Response", response)
    return response  # Return the response if it's needed for the Lambda function's behavior

#perhaps we make another elif block where if all slot values are filled, we run the parsing function

# """"in the final else block we should be able to retrieve the session attributes and use that to
#the name, we can use for the ordered_items, and the pick up time. I think regardless it should work.

#sessionAttributes can be use to guide the conversation based on previous interactions, for e.g. if the user has already provided their name or if they have elect certain options - perhaps can be used to recall customers previous order

